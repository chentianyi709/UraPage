import Foundation
import Kingfisher
import Observation
import UIKit

/// 把来源的稳定缓存身份与实际请求交给 Kingfisher，由后者完成下载、处理与缓存。
private struct BrowsingImageResource: Resource {
    let cacheKey: String
    let downloadURL: URL
}

/// 一次浏览体验独占的普通图片工作域：共享全局内存池与共享磁盘，只独占本体验的在途请求。
///
/// - 内存是 App 全局共享池（`BrowsingImageConfiguration.memoryCostLimit`），磁盘只保存服务器原始数据；
///   切源只取消本工作域的在途请求，不清空共享内存池，其它来源已缓存的显示图仍可复用。
/// - 持有从“查缓存、准备来源请求、下载、处理”到缓存的完整工作；
///   同一缓存身份 + 目标尺寸 + scale 的并发请求复用同一个在途任务。
/// - View 只订阅结果，结束等待不取消共享工作；`close()` 统一取消在途任务。
/// - 来源图片环境变化时用 `invalidateInFlight()` 只取消在途请求：缓存身份不变，
///   已缓存或已显示的图片保留；正在等待的 View 通过 `requestGeneration` 重新发起请求。
@MainActor
@Observable
final class BrowsingImageScope {
    @ObservationIgnored private let cache: ImageCache
    @ObservationIgnored private let manager: KingfisherManager

    /// 在途工作；key 由稳定缓存身份、目标尺寸、scale 与请求代次组合。
    @ObservationIgnored private var tasks: [LoadKey: Task<UIImage, any Error>] = [:]
    @ObservationIgnored private var isClosed = false

    /// 请求代次：`invalidateInFlight()` 时递增，正在加载的 `ComicImageView` 据此重试。
    ///
    /// 代次只用于区分新旧在途请求，不参与缓存身份，也不清除共享缓存。
    private(set) var requestGeneration = 0

    /// 使用 App 全局共享缓存（内存池 + 磁盘）创建页面级工作域。
    init(cache: ImageCache) {
        self.cache = cache
        let downloader = ImageDownloader(name: "browsing.scope.\(UUID().uuidString)")
        // 显式指定下载超时，不用 Kingfisher 默认值。
        downloader.downloadTimeout = BrowsingImageConfiguration.downloadTimeout
        manager = KingfisherManager(
            downloader: downloader,
            cache: cache,
        )
    }

    /// 取得指定展示尺寸的图片。
    ///
    /// 先查显示尺寸的内存缓存，再读取原始磁盘数据并后台降采样；都未命中才请求来源。
    /// `downsamples` 为 `false` 时不做降采样，直接显示原图（详情页大图与长按预览用，保证清晰度）。
    /// 失败或取消抛出原始错误，由 View 决定展示占位。
    func image(
        for reference: ComicImageReference,
        targetSize: CGSize,
        displayScale: CGFloat,
        downsamples: Bool = true,
        using imageService: any ComicImageService,
    ) async throws -> UIImage {
        guard !isClosed else {
            throw CancellationError()
        }

        // 缓存身份纯本地；命中不读取 Host/Setting。
        let sourceResource = try imageService.resource(for: reference)
        let key = LoadKey(
            cacheKey: sourceResource.cacheKey,
            width: targetSize.width,
            height: targetSize.height,
            scale: max(displayScale, 1),
            downsamples: downsamples,
            generation: requestGeneration,
        )

        if let inFlight = tasks[key] {
            return try await inFlight.value
        }

        // 第一次挂起前登记完整工作，缓存查询也受去重和 close 屏障管理。
        let task = Task { @MainActor in
            defer { tasks[key] = nil }
            try Task.checkCancellation()
            if let cachedImage = cache.retrieveImageInMemoryCache(
                forKey: sourceResource.cacheKey,
                options: displayOptions(
                    targetSize: targetSize,
                    scale: displayScale,
                    downsamples: downsamples,
                ),
            ) {
                return cachedImage
            }

            let originalData = try await originalImageData(forKey: sourceResource.cacheKey)
            try Task.checkCancellation()
            if let originalData {
                // 直接用压缩数据降采样，避免 Kingfisher 的原图缓存路径先生成全尺寸位图。
                // forceRefresh 在 DataProvider 上仅跳过缓存查询，不会发起网络请求或改写原始数据。
                let provider = RawImageDataProvider(data: originalData, cacheKey: sourceResource.cacheKey)
                let options = displayOptions(
                    targetSize: targetSize,
                    scale: displayScale,
                    downsamples: downsamples,
                ) + [.forceRefresh]
                do {
                    let result = try await manager.retrieveImage(with: .provider(provider), options: options)
                    try Task.checkCancellation()
                    return result.image
                } catch KingfisherError.processorError {
                    // 仅解码失败代表原始缓存损坏；取消、权限和其它 IO 错误继续向上传递。
                    try Task.checkCancellation()
                    AppLogger.warning("普通图片原始缓存无法解码，移除损坏条目后重新请求", category: "App.Image")
                    try await cache.removeImage(
                        forKey: sourceResource.cacheKey,
                        fromMemory: false,
                        fromDisk: true,
                    )
                }
            }

            return try await download(
                sourceResource: sourceResource,
                targetSize: targetSize,
                displayScale: displayScale,
                downsamples: downsamples,
                imageService: imageService,
            )
        }
        tasks[key] = task

        return try await task.value
    }

    /// 原始压缩数据按来源 key 读取；磁盘 IO 与过期检查离开 MainActor 执行。
    @concurrent
    private func originalImageData(forKey cacheKey: String) async throws -> Data? {
        try cache.diskStorage.value(forKey: cacheKey)
    }

    /// 取消本 scope 的在途请求并递增请求代次；共享缓存与已显示图片不受影响。
    ///
    /// 用于来源图片环境（例如图片 Host）成功切换后：旧环境发起的请求可能已不可用，
    /// 取消后由正在等待的 View 立即按新环境重新请求。失败或已完成的请求不在这里处理。
    func invalidateInFlight() {
        guard !isClosed else {
            return
        }

        let pending = Array(tasks.values)
        AppLogger.debug("图片请求环境变化，取消在途任务=\(pending.count)", category: "App.Image")
        for task in pending {
            task.cancel()
        }
        requestGeneration += 1
    }

    /// 关闭本 scope：标记关闭、取消并等待在途工作；共享内存池与磁盘都保留给其它来源／页面。
    func close() async {
        guard !isClosed else {
            return
        }

        isClosed = true

        let pending = Array(tasks.values)
        AppLogger.debug("关闭图片工作域，取消在途任务=\(pending.count)", category: "App.Image")
        tasks.removeAll()
        for task in pending {
            task.cancel()
        }
        // 并行等待所有在途任务退出；逐个 await 会让关闭耗时随任务数量线性增长。
        await withTaskGroup(of: Void.self) { group in
            for task in pending {
                group.addTask {
                    _ = try? await task.value
                }
            }
        }
    }

    /// 下载保存服务器原始数据，显示图只放内存；等待原始数据写盘完成再结束共享工作。
    private func download(
        sourceResource: SourceImageResource,
        targetSize: CGSize,
        displayScale: CGFloat,
        downsamples: Bool,
        imageService: any ComicImageService,
    ) async throws -> UIImage {
        let request = try await imageService.request(for: sourceResource)
        try Task.checkCancellation()
        guard let url = request.url else {
            throw ComicSourceError.invalidResponse
        }

        // 用来源构造的完整请求覆盖 Kingfisher 的裸 GET（Host/Header/认证/CDN）。
        let modifier = AnyModifier { _ in request }
        let resource = BrowsingImageResource(cacheKey: sourceResource.cacheKey, downloadURL: url)
        // 缓存查询已经完成，不再进入 Manager 会解码全尺寸原图的自动缓存路径。
        let options = displayOptions(
            targetSize: targetSize,
            scale: displayScale,
            downsamples: downsamples,
        ) +
            [.forceRefresh, .requestModifier(modifier)]

        let result = try await manager.retrieveImage(with: resource, options: options)
        try Task.checkCancellation()
        // forceRefresh 保证结果来自下载，data() 直接返回响应字节，不重新编码显示图。
        // 显式等待写盘并传播错误，避免自动原图缓存与仅内存缓存组合的回调问题。
        guard let originalData = result.data() else {
            throw ComicSourceError.invalidResponse
        }

        try await cache.storeToDisk(originalData, forKey: sourceResource.cacheKey)
        try Task.checkCancellation()
        return result.image
    }

    /// 所有显示路径共用采样参数；处理结果只放体验内存，不按显示尺寸重复写磁盘。
    ///
    /// `downsamples` 为 `false` 时不加处理器：内存 key 退回裸缓存身份，
    /// 与各降采样变体互不覆盖，直接保留原始像素。
    private func displayOptions(
        targetSize: CGSize,
        scale: CGFloat,
        downsamples: Bool,
    ) -> KingfisherOptionsInfo {
        var options: KingfisherOptionsInfo = [
            .scaleFactor(max(scale, 1)),
            .backgroundDecode,
            .cacheMemoryOnly,
        ]
        if downsamples {
            options.insert(.processor(DownsamplingImageProcessor(size: targetSize)), at: 0)
        }
        return options
    }

    /// 保留真实尺寸、scale、是否降采样与请求代次，避免不同显示需求或新旧环境误共用同一个在途任务。
    private struct LoadKey: Hashable {
        let cacheKey: String
        let width: CGFloat
        let height: CGFloat
        let scale: CGFloat
        let downsamples: Bool
        let generation: Int
    }
}

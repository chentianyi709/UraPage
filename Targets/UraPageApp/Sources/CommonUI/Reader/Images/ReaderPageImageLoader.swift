import Foundation
import Kingfisher
import UIKit

/// 从共享页面载荷入口取得页面，并在非 MainActor 上准备当前显示位图。
final nonisolated class ReaderPageImageLoader: Sendable {
    typealias ImagePresenter = @MainActor @Sendable (UIImage) -> Void

    /// 保存像素处理结果以及正式缓存可以复用的原始编码数据。
    struct ProcessedPage: Sendable {
        let cacheImage: UIImage
        let displayImage: UIImage
        let originalData: Data?

        #if DEBUG
            let decodingDuration: Duration
        #endif
    }

    let cache: ImageCache
    let cacheLease: ReaderImageCacheLease
    private let cacheWriter: ReaderPageCacheWriter

    /// 使用当前 ReaderSession 的缓存 lease 创建页面加载器。
    init(cacheLease: ReaderImageCacheLease) {
        self.cacheLease = cacheLease
        cache = cacheLease.cache
        cacheWriter = ReaderPageCacheWriter(cache: cache)
    }

    /// Reader 退出时释放自己的图片 ownership。
    func close() async {
        await cacheLease.release()
    }

    /// 优先读取内存或磁盘缓存；缺失时直接请求来源，并在正式写盘前提交显示图。
    @concurrent
    func loadImage(
        for page: ComicPage,
        displayMode: ReaderPageImageDisplayMode,
        pageAccess: ReaderPageAccess,
        onImagePrepared: @escaping ImagePresenter,
    ) async throws {
        try Task.checkCancellation()
        let cacheKey = ReaderPageCacheKey.make(for: page.identity)
        let memoryCacheKey = Self.memoryCacheKey(
            cacheKey: cacheKey,
            displayMode: displayMode,
            sessionNamespace: pageAccess.sessionMemoryNamespace,
        )
        await cacheLease.acquire(memoryCacheKey)
        // Reader 内存缓存只保留静态显示位图，命中即直接复用；
        // 动画显示图按设计不写内存缓存（由图片窗口持有），会落到载荷读取（磁盘优先，不联网重下）。
        if let memoryImage = cache.retrieveImageInMemoryCache(forKey: memoryCacheKey) {
            await onImagePrepared(memoryImage)
            return
        }

        switch pageAccess {
        case let .online(_, loadPage):
            try await loadOnlinePage(
                page,
                cacheKey: cacheKey,
                memoryCacheKey: memoryCacheKey,
                displayMode: displayMode,
                loadPage: loadPage,
                onImagePrepared: onImagePrepared,
            )

        case let .downloadedAsset(_, payload):
            try await loadDownloadedPage(
                page,
                memoryCacheKey: memoryCacheKey,
                displayMode: displayMode,
                payload: payload,
                onImagePrepared: onImagePrepared,
            )
        }
    }

    /// 通过共享下载器取得页面载荷，再准备并显示当前 Reader 位图。
    private func loadOnlinePage(
        _ page: ComicPage,
        cacheKey: String,
        memoryCacheKey: String,
        displayMode: ReaderPageImageDisplayMode,
        loadPage: @escaping ReaderPageAccess.OnlinePageLoader,
        onImagePrepared: @escaping ImagePresenter,
    ) async throws {
        try Task.checkCancellation()
        AppLogger.debug(
            "Reader 开始获取在线页面，chapterID=\(page.identity.chapter.chapterID)，chapterPage=\(page.index + 1)",
            category: "Reader.Page",
        )

        #if DEBUG
            let clock = ContinuousClock()
        #endif

        do {
            try await loadPage(page) { payload in
                try Task.checkCancellation()
                #if DEBUG
                    let decodingStartedAt = clock.now
                #endif
                let preparedImage = try await ReaderPageImagePreparer.prepare(
                    payload,
                    displayMode: displayMode,
                )
                try Task.checkCancellation()

                #if DEBUG
                    let processedPage = ProcessedPage(
                        cacheImage: preparedImage.cacheImage,
                        displayImage: preparedImage.displayImage,
                        originalData: payload.encodedData,
                        decodingDuration: decodingStartedAt.duration(to: clock.now),
                    )
                #else
                    let processedPage = ProcessedPage(
                        cacheImage: preparedImage.cacheImage,
                        displayImage: preparedImage.displayImage,
                        originalData: payload.encodedData,
                    )
                #endif

                storeMemoryImage(
                    processedPage.displayImage,
                    forKey: memoryCacheKey,
                )
                await onImagePrepared(processedPage.displayImage)
                try Task.checkCancellation()
                await cacheWriter.store(
                    processedPage,
                    forKey: cacheKey,
                )

                #if DEBUG
                    AppLogger.debug(
                        "Reader 页面加载完成，chapterID=\(page.identity.chapter.chapterID)，chapterPage=\(page.index + 1)，decodeMs=\(Self.milliseconds(processedPage.decodingDuration))",
                        category: "Reader.Page",
                    )
                #endif
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            let nsError = error as NSError
            AppLogger.error(
                "Reader 页面加载失败，chapterID=\(page.identity.chapter.chapterID)，chapterPage=\(page.index + 1)，errorType=\(String(reflecting: type(of: error)))，domain=\(nsError.domain)，code=\(nsError.code)",
                category: "Reader.Page",
            )
            throw ReaderPageFailure.map(error, fallback: .networkUnavailable)
        }
    }

    /// 只从 DownloadManager 暴露的受控 payload API 读取，不创建临时文件或磁盘缓存。
    private func loadDownloadedPage(
        _ page: ComicPage,
        memoryCacheKey: String,
        displayMode: ReaderPageImageDisplayMode,
        payload: @escaping ReaderPageAccess.DownloadedPayload,
        onImagePrepared: @escaping ImagePresenter,
    ) async throws {
        try Task.checkCancellation()
        AppLogger.debug(
            "Reader 开始读取本地资产，chapterID=\(page.identity.chapter.chapterID)，chapterPage=\(page.index + 1)",
            category: "Reader.Page",
        )

        do {
            let sourcePayload = try await payload(page)
            try Task.checkCancellation()
            let preparedImage = try await ReaderPageImagePreparer.prepare(
                sourcePayload,
                displayMode: displayMode,
            )
            try Task.checkCancellation()
            storeMemoryImage(
                preparedImage.displayImage,
                forKey: memoryCacheKey,
            )
            await onImagePrepared(preparedImage.displayImage)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            let nsError = error as NSError
            AppLogger.error(
                "Reader 本地资产读取失败，chapterID=\(page.identity.chapter.chapterID)，chapterPage=\(page.index + 1)，errorType=\(String(reflecting: type(of: error)))，domain=\(nsError.domain)，code=\(nsError.code)",
                category: "Reader.Page",
            )
            throw ReaderPageFailure.map(
                error,
                fallback: .localAssetCorrupted,
            )
        }
    }

    #if DEBUG
        /// 把单调时钟的耗时转换为日志使用的整数毫秒。
        private static func milliseconds(_ duration: Duration) -> Int64 {
            Int64(duration / .milliseconds(1))
        }
    #endif
}

private extension SourcePagePayload {
    /// 仅在来源保留了原始编码图片时把数据交给磁盘缓存。
    nonisolated var encodedData: Data? {
        guard case let .encoded(data) = self else {
            return nil
        }

        return data
    }
}

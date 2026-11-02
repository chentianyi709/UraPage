import Foundation
import Kingfisher
import UIKit

/// App 进程内唯一的普通图片缓存 owner：一份共享内存池 + 一份共享磁盘。
///
/// 由 composition root 创建一次并长期持有；页面级 `BrowsingImageScope` 与离线封面
/// 都从它取得同一份内存池，因此非阅读图片的内存总量受固定上限约束（不再每个来源各一份）。
/// App 与来源层都不直接接触 Kingfisher 类型。
/// 作品下载通过稳定缓存身份复用原始图片字节；通用设置页通过它读取占用、清空缓存与调整磁盘上限。
@MainActor
final class BrowsingImageStore: BrowsingImageCacheReading {
    /// 共享内存池句柄；浏览工作域与已下载封面共用的唯一入口。
    let memoryPool: ImageMemoryPool

    /// 共享缓存：内存是全局池，磁盘只保存服务器返回的原始数据。
    private let imageCache: ImageCache

    /// 创建共享内存池与磁盘缓存；初始磁盘上限取 `BrowsingImageConfiguration` 默认值，
    /// 组合根随后用通用设置里持久化的上限覆盖（`setDiskSizeLimit(bytes:)`）。
    init() throws {
        let diskStorage = try DiskStorage.Backend<Data>(
            config: DiskStorage.Config(
                name: BrowsingImageConfiguration.diskCacheName,
                sizeLimit: UInt(BrowsingImageConfiguration.defaultDiskSizeLimit),
            ),
        )
        let memoryStorage = MemoryStorage.Backend<UIImage>(
            config: MemoryStorage.Config(
                totalCostLimit: BrowsingImageConfiguration.memoryCostLimit,
                cleanInterval: BrowsingImageConfiguration.memoryCleanInterval,
            ),
        )
        let imageCache = ImageCache(memoryStorage: memoryStorage, diskStorage: diskStorage)
        self.imageCache = imageCache
        memoryPool = ImageMemoryPool(cache: imageCache)
    }

    /// 用共享缓存创建新的页面级图片工作域（共用全局内存池 + 共享磁盘）。
    func makeScope() -> BrowsingImageScope {
        BrowsingImageScope(cache: imageCache)
    }

    /// 查找普通图片缓存中的原始服务器文件；缓存缺失或过期时返回 nil。
    @concurrent
    func cachedOriginalFile(for resource: SourceImageResource) async throws -> URL? {
        guard imageCache.diskStorage.isCached(forKey: resource.cacheKey) else { return nil }

        return imageCache.diskStorage.cacheFileURL(forKey: resource.cacheKey)
    }

    /// 当前磁盘缓存占用（字节）；目录枚举是同步 IO，因此离开调用方执行器执行。
    @concurrent
    func totalDiskSize() async throws -> Int {
        try Int(imageCache.diskStorage.totalSize())
    }

    /// 清空共享磁盘缓存；同样离开调用方执行器。
    @concurrent
    func clearDiskCache() async throws {
        try imageCache.diskStorage.removeAll()
    }

    /// 更新磁盘缓存上限；Kingfisher 在后续写入时按新上限回收，不必重建后端（各 scope 共享同一实例）。
    func setDiskSizeLimit(bytes: Int) {
        imageCache.diskStorage.config.sizeLimit = UInt(bytes)
    }
}

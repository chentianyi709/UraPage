import Foundation
import Kingfisher

/// 图片先显示，再由页面任务等待正式缓存写入；关闭 session 时可以等待写盘结束。
actor ReaderPageCacheWriter {
    private let cache: ImageCache
    init(cache: ImageCache) {
        self.cache = cache
    }

    /// 不额外限制并发；只等待当前页面的写入回调，不把失败伪装成成功缓存。
    func store(_ page: ReaderPageImageLoader.ProcessedPage, forKey key: String) async {
        await withCheckedContinuation { continuation in
            let completion: @Sendable (CacheStoreResult) -> Void = { result in
                if case let .failure(error) = result.diskCacheResult {
                    AppLogger.warning(
                        "Reader 页面缓存写入失败，errorType=\(String(reflecting: type(of: error)))",
                        category: "Reader.Cache",
                    )
                }
                continuation.resume()
            }
            if let originalData = page.originalData {
                cache.storeToDisk(originalData, forKey: key, completionHandler: completion)
            } else {
                cache.store(
                    page.cacheImage,
                    forKey: key,
                    completionHandler: completion,
                )
                // 正式 Key 只承担磁盘身份，显示位图使用独立内存变体。
                cache.removeImage(forKey: key, fromMemory: true, fromDisk: false)
            }
        }
    }
}

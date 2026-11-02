import Foundation
import Kingfisher

/// `ChapterImageCacheReading` 的 Kingfisher 适配：按完整 `PageIdentity` 读取 Reader 正式磁盘缓存。
///
/// 下载前先查这里，命中即复用缓存字节；缺失按未命中处理，不检查图像解码或完整性。
struct ReaderChapterImageCache: ChapterImageCacheReading {
    let store: ReaderImageCacheStore

    @concurrent
    func cachedPageData(for identity: PageIdentity) async throws -> Data? {
        do {
            return try store.cache.diskStorage.value(forKey: ReaderPageCacheKey.make(for: identity))
        } catch let error as KingfisherError {
            if case let .cacheError(reason) = error {
                switch reason {
                case let .cannotLoadDataFromDisk(_, underlyingError),
                     let .invalidURLResource(underlyingError, _, _):
                    if Self.isMissingFile(underlyingError) {
                        return nil
                    }

                default:
                    break
                }
            }
            throw error
        }
    }

    private static func isMissingFile(_ error: any Error) -> Bool {
        let error = error as NSError
        return error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError
    }
}

import Kingfisher
import SwiftUI
import UIKit

/// 非阅读图片的共享内存池：所有来源的浏览图片与已下载封面共用同一份固定上限的内存缓存。
///
/// 只负责内存读写（不查磁盘、不联网、不含来源能力）。缓存身份由调用方提供：
/// 浏览图片用来源生成的 `SourceImageCacheKey`，已下载封面用本地 key 前缀，二者不冲突。
/// 上限固定为 `BrowsingImageConfiguration.memoryCostLimit`，不随来源或页面变化。
@MainActor
final class ImageMemoryPool {
    private let cache: ImageCache

    init(cache: ImageCache) {
        self.cache = cache
    }

    /// 读取池中已解码的显示图；不存在时返回 `nil`。
    func image(forKey key: String) -> UIImage? {
        cache.retrieveImageInMemoryCache(forKey: key)
    }

    /// 只把已解码的显示图放进池，不写磁盘。
    func store(_ image: UIImage, forKey key: String) {
        cache.store(image, forKey: key, toDisk: false) { _ in }
    }
}

extension EnvironmentValues {
    /// 非阅读图片的共享内存池存储槽；写入用 `\.imageMemoryPoolStorage`（写入路径先读缺省，缺省必须可读）。
    @Entry var imageMemoryPoolStorage: ImageMemoryPool?

    /// 读取入口：由 App 入口安装，浏览图片与已下载封面共用，未安装即暴露装配错误。
    var imageMemoryPool: ImageMemoryPool {
        guard let imageMemoryPoolStorage else {
            preconditionFailure("imageMemoryPool 未由 App 入口安装")
        }

        return imageMemoryPoolStorage
    }
}

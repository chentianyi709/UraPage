import SwiftUI

/// 向 ReaderSession 提供 App 组装层创建的专用图片缓存和 lease 工厂。
extension EnvironmentValues {
    /// Reader 专用图片缓存存储槽；写入用 `\.readerImageCacheStorage`（写入路径先读缺省，缺省必须可读）。
    @Entry var readerImageCacheStorage: ReaderImageCacheStore?

    /// 读取入口：由 App 入口安装，未安装即暴露装配错误。
    ///
    /// 专用而不复用公共缓存：Reader 退出清理不能波及封面和头像使用的 ImageCache.default。
    var readerImageCache: ReaderImageCacheStore {
        guard let readerImageCacheStorage else {
            preconditionFailure("Reader 图片缓存未由 App 入口安装")
        }

        return readerImageCacheStorage
    }
}

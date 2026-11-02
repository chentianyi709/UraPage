import Foundation

/// 普通浏览图片的固定策略；属于待真机验证的初始值，集中在此便于统一调整。
enum BrowsingImageConfiguration {
    /// 非阅读图片的全局共享内存池上限；固定不可修改（512 MiB）。
    ///
    /// 所有来源的浏览图片与已下载封面共用这一份内存池（`ImageMemoryPool`），
    /// 不随来源或页面各自计费；超出上限由 Kingfisher 按 cost 回收，系统内存警告也会清理。
    static let memoryCostLimit = 512 * 1024 * 1024

    /// 共享内存池过期条目的清理间隔（秒）。
    static let memoryCleanInterval: TimeInterval = 120

    /// 普通浏览图片单次下载请求超时（秒）；显式指定，不用 Kingfisher 默认值。
    static let downloadTimeout: TimeInterval = 30

    /// 共享图片磁盘缓存的默认上限（5 GiB）。
    ///
    /// 实际生效值来自通用设置的缓存上限档位（`ImageCacheSettingsStore` 持久化：
    /// 默认 5 GiB、最小 1 GiB、最大 10 GiB）；此常量只作首次启动与无设置时的兜底。
    static let defaultDiskSizeLimit = 5 * 1024 * 1024 * 1024

    /// 磁盘缓存上限允许的最小档位（1 GiB）。
    static let minimumDiskSizeLimit = 1 * 1024 * 1024 * 1024

    /// 磁盘缓存上限允许的最大档位（10 GiB）。
    static let maximumDiskSizeLimit = 10 * 1024 * 1024 * 1024

    /// 共享磁盘缓存名称；不随来源或 scope 变化，避免多个磁盘实例指向同一目录。
    static let diskCacheName = "browsing.images.v1"
}

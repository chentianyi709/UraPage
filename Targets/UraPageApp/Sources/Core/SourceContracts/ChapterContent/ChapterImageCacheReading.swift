import Foundation

/// 查询并读取 Reader 正式磁盘缓存，供下载复用已缓存页面。
///
/// 由 CommonUI 适配层实现（Kingfisher 磁盘缓存只在那里使用）；命中时直接返回缓存字节，
/// 缺失按未命中处理；其它读取错误向调用方传播。
protocol ChapterImageCacheReading: Sendable {
    /// 返回完整页面身份对应的缓存字节；未缓存返回 `nil`，磁盘读取错误抛出。
    @concurrent
    func cachedPageData(for identity: PageIdentity) async throws -> Data?
}

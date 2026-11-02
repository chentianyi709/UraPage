import Foundation

/// 读取普通图片缓存中的服务器原始文件，供作品封面直接复制到下载资产目录。
///
/// 缓存缺失或已过期返回 `nil`；其它文件读取错误向下载流程传播。
protocol BrowsingImageCacheReading: Sendable {
    /// 按来源生成的稳定缓存身份返回原始图片文件；不读取字节或执行图片解码。
    @concurrent
    func cachedOriginalFile(for resource: SourceImageResource) async throws -> URL?
}

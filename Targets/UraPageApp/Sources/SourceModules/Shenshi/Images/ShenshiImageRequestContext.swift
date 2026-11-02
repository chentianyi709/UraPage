import Foundation

/// 分别解析绅士图片的稳定缓存身份和依赖运行时环境的实际请求。
final class ShenshiImageRequestContext: Sendable {
    /// 只使用稳定 locator 生成可在 Host 准备前查询的缓存身份。
    ///
    /// 绅士当前不使用 query 区分内容，identityURL 显式只取 path；将来需要时在这里保留
    /// 对应查询参数即可，公共生成器已支持非空 query。
    func resource(for reference: ComicImageReference) throws -> SourceImageResource {
        let identityURL = try SourceImageURLResolver.resolve(
            reference.locator,
            relativeTo: SourceImageURLResolver.cacheIdentityBaseURL,
        )
        return SourceImageResource(
            reference: reference,
            cacheKey: SourceImageCacheKey.make(
                for: reference,
                identityURL: SourceImageIdentity.urlWithoutQuery(identityURL),
            ),
        )
    }

    /// 缓存未命中后，使用明确的页面 Host 和 User-Agent 组成完整请求。
    func request(for reference: ComicImageReference, baseURL: URL, userAgent: String) throws -> URLRequest {
        let imageURL = try SourceImageURLResolver.resolve(reference.locator, relativeTo: baseURL)
        var request = URLRequest(url: imageURL)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(baseURL.absoluteString, forHTTPHeaderField: "Referer")
        return request
    }
}

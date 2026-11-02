import Foundation

/// 分别解析禁漫图片的稳定缓存身份和依赖运行时图片 Host 的实际请求。
final class JMComicImageRequestContext: Sendable {
    /// 只使用稳定 locator 生成可在 Setting 准备前查询的缓存身份。
    ///
    /// 封面在身份侧去掉请求专用的 `?v=`（见 `JMComicCoverIdentity`），其余用途原样使用
    /// locator；query 是否参与身份由各来源的 identityURL 决定。
    func resource(for reference: ComicImageReference) throws -> SourceImageResource {
        let identityURL = try identityURL(
            for: reference,
            relativeTo: SourceImageURLResolver.cacheIdentityBaseURL,
        )
        return SourceImageResource(
            reference: reference,
            cacheKey: SourceImageCacheKey.make(for: reference, identityURL: identityURL),
        )
    }

    /// 缓存未命中后，使用当前 Setting 的图片 Host 组成完整请求；请求保留 locator 的完整 query。
    func request(for reference: ComicImageReference, imageHost: URL) throws -> URLRequest {
        try URLRequest(url: requestImageURL(for: reference, relativeTo: imageHost))
    }

    /// 禁漫头像接口可能只返回文件名；其它用途直接使用 locator。
    private func resolvedLocator(for reference: ComicImageReference) throws -> String {
        guard reference.purpose == .avatar else {
            return reference.locator
        }

        let locator = reference.locator.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !locator.isEmpty else {
            throw ComicSourceError.invalidResponse
        }

        // 完整 URL 或已经包含目录的相对路径不再重复拼接。
        guard !locator.contains("/") else {
            return locator
        }

        return JMComicConfiguration.Image.defaultAvatarRelativePath(fileName: locator)
    }

    /// 缓存身份 URL：封面去掉 `v` 版本参数，其余用途使用解析后的 locator。
    private func identityURL(
        for reference: ComicImageReference,
        relativeTo baseURL: URL,
    ) throws -> URL {
        let locator = try resolvedLocator(for: reference)
        let identityLocator = reference.purpose == .cover
            ? JMComicCoverIdentity.locatorWithoutVersion(locator)
            : locator

        return try SourceImageURLResolver.resolve(identityLocator, relativeTo: baseURL)
    }

    /// 实际请求 URL：使用完整 locator（封面带 `?v=`）。
    private func requestImageURL(
        for reference: ComicImageReference,
        relativeTo baseURL: URL,
    ) throws -> URL {
        try SourceImageURLResolver.resolve(resolvedLocator(for: reference), relativeTo: baseURL)
    }
}

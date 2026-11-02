import Foundation

/// 普通图片的稳定身份分量：path 与参与身份的 query。
///
/// 远程缓存 Key 与下载封面文件名共用同一套解析，避免两处各自处理相对地址、百分号编码
/// 或 Host 时产生不一致。Host、scheme 与 fragment 不参与身份；query 是否参与由来源
/// 组装的 identityURL / locator 决定（临时签名、版本号等由来源在来源侧剔除）。
enum SourceImageIdentity {
    /// 从已解析的图片 URL 取 path 与非空 query；解析失败时退回原始 path。
    static func components(of url: URL) -> (path: String, query: String?) {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let path = components?.percentEncodedPath ?? url.path
        return (path, normalizedQuery(components?.percentEncodedQuery))
    }

    /// 从 locator 取 path 与非空 query；完整地址、协议相对地址或相对路径都可以。
    static func components(ofLocator locator: String) -> (path: String, query: String?) {
        guard let components = URLComponents(string: locator) else {
            return (locator, nil)
        }

        return (components.percentEncodedPath, normalizedQuery(components.percentEncodedQuery))
    }

    /// 拼成稳定的文件身份：有 query 时为 `path?query`，否则只有 path。
    static func pathAndQuery(ofLocator locator: String) -> String {
        let components = components(ofLocator: locator)
        guard let query = components.query else { return components.path }

        return "\(components.path)?\(query)"
    }

    /// 去掉查询参数的 URL；不需要 query 身份的来源用它组装 path-only identityURL。
    static func urlWithoutQuery(_ url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }

        components.percentEncodedQuery = nil
        return components.url ?? url
    }

    private static func normalizedQuery(_ query: String?) -> String? {
        guard let query, !query.isEmpty else { return nil }

        return query
    }
}

import Foundation

/// 把来源已编码的相对 URL 的 path 与 query 拼接到当前 Base URL。
///
/// 各来源的请求适配器共用此规则，避免三份重复实现。
/// 返回 `nil` 表示相对地址缺失或无法组合，由调用方按来源错误边界处理。
enum SourceRelativeURL {
    /// 组合绝对地址；`relativeURL` 为 `nil` 时返回 `nil`。
    static func absolute(_ relativeURL: URL?, base: URL) -> URL? {
        guard let relativeURL else {
            return nil
        }

        let relativeComponents = URLComponents(url: relativeURL, resolvingAgainstBaseURL: false)
        let relativePath = relativeURL.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let absoluteURL = relativePath.isEmpty ? base : base.appending(path: relativePath)

        var absoluteComponents = URLComponents(url: absoluteURL, resolvingAgainstBaseURL: false)
        absoluteComponents?.percentEncodedQuery = relativeComponents?.percentEncodedQuery

        return absoluteComponents?.url
    }
}

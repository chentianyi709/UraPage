import Foundation

/// 来源图片 locator 的公共解析：完整地址、协议相对地址或相对业务 Host 的路径。
///
/// 缓存身份与实际请求共用同一套解析规则；需要额外改写 locator 的来源（如禁漫头像文件名）
/// 先在自己的私有规则里改写，再交给本类型。
enum SourceImageURLResolver {
    /// 仅用于规范化相对 locator 的缓存身份基址；无效 origin 不参与缓存 Key，也不会发起请求。
    static let cacheIdentityBaseURL = URL(string: "https://image-cache.invalid/")!

    /// 解析 locator：`//` 前缀补 HTTPS，完整地址原样使用，其它相对路径相对给定 Host 解析。
    static func resolve(_ locator: String, relativeTo baseURL: URL) throws -> URL {
        if locator.hasPrefix("//") {
            // 网页可能返回 `//域名/路径`，统一移除前导斜杠后再补充 HTTPS 协议。
            let hostAndPath = locator.drop(while: { $0 == "/" })
            guard !hostAndPath.isEmpty, let url = URL(string: "https://\(hostAndPath)") else {
                throw ComicSourceError.invalidResponse
            }

            return url
        }

        if let absoluteURL = URL(string: locator), absoluteURL.scheme != nil, absoluteURL.host != nil {
            return absoluteURL
        }
        guard let relativeURL = URL(string: locator, relativeTo: baseURL)?.absoluteURL else {
            throw ComicSourceError.invalidResponse
        }

        return relativeURL
    }
}

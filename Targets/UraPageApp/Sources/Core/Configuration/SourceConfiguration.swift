import Foundation

/// 集中来源公共的固定策略与标识符（所有来源共用，不属于任何具体来源）。
///
/// 只放不随构建环境变化、也不属于具体来源的纯值和固定策略；
/// 来源协议常量放各自 Source 的 `Infrastructure/Configuration/<来源>Configuration.swift`。
/// 可变设置、当前 Host 与远端响应不进入这里。
enum SourceConfiguration {
    /// 来源业务 Session 的超时与连通性；不改变调用方的 Cookie、缓存或 Header。
    enum Session {
        /// 普通业务请求超时（秒）。
        static let requestTimeout: TimeInterval = 30

        /// 普通业务资源整体超时（秒）。
        static let resourceTimeout: TimeInterval = 60

        /// 章节页面请求超时（秒）。
        static let pageRequestTimeout: TimeInterval = 30

        /// 章节页面资源整体超时（秒）。
        static let pageResourceTimeout: TimeInterval = 300

        /// 应用普通业务超时，不改变 Cookie、缓存、Header 或存储类型。
        static func applyDefaults(to configuration: URLSessionConfiguration) {
            configuration.timeoutIntervalForRequest = requestTimeout
            configuration.timeoutIntervalForResource = resourceTimeout
            // 暂时无网络时等待连通而不是立即失败；是否继续由上层取消语义决定。
            configuration.waitsForConnectivity = true
        }

        /// 独立业务 Session 的公共设置：不由 URLSession 隐式保存 Cookie 或响应缓存。
        static func applyCookieFreeDefaults(to configuration: URLSessionConfiguration) {
            applyDefaults(to: configuration)
            configuration.httpShouldSetCookies = false
            configuration.httpCookieStorage = nil
            configuration.urlCache = nil
        }

        /// 创建章节页传输用的前台临时配置，不落 URLCache、不使用本地缓存。
        /// 来源各自持有 Session，在前台通过统一传输方法下载页面。
        static func pageTransferConfiguration() -> URLSessionConfiguration {
            let configuration = URLSessionConfiguration.ephemeral
            applyDefaults(to: configuration)
            configuration.timeoutIntervalForRequest = pageRequestTimeout
            configuration.timeoutIntervalForResource = pageResourceTimeout
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            configuration.urlCache = nil
            return configuration
        }
    }

    /// 公共存储标识符；Bundle Identifier 前缀由 `AppIdentifierNamespace` 生成，
    /// 版本段写在各 key 字符串里（破坏性变更只递增对应 key），读写留在各 owner。
    enum Storage {
        /// Keychain service：来源凭证，以 `sourceID` 作为 account 隔离。
        static let sourceCredentials = AppIdentifierNamespace.make("v1.source-credentials")

        /// 指定来源已选 Host 偏好 Key。
        static func hostSelection(for sourceID: ComicSourceID) -> String {
            AppIdentifierNamespace.make("v1.host-selection.\(sourceID.rawValue)")
        }

        /// 指定客户端平台的 User-Agent 缓存 Key。
        static func userAgent(for platform: SourceUserAgentPlatform) -> String {
            AppIdentifierNamespace.make("v1.user-agent.\(platform.rawValue)")
        }
    }
}

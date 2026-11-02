import Foundation

/// 哔咔来源的固定协议常量与持久化标识符。
///
/// 可变设置、当前 CDN 开关与远端响应由各自 owner 管理；
/// 这里只集中不随构建环境变化的协议值和存储 Key。
enum BikaConfiguration {
    /// 哔咔业务 API 的签名材料和固定请求头。
    ///
    /// 这些值是客户端协议要求、可从 App 二进制恢复的公开常量，不是用户凭证。
    /// 真实账号、Token 和 Cookie 不得放在这里。
    enum API {
        /// 协议用于识别客户端请求的固定 API key（非秘密）。
        static let apiKey = "C69BAF41DA5ABD1FFEDC6D2FEA56B"

        /// 参与请求 HMAC-SHA256 签名计算的固定协议材料（非秘密）。
        static let signatureSecret = "~d}$Q7$eIni=V)9\\RK/P.RM4;9[7|@/CA}b~OW!3?EV`:<>M7pddUBL5n|0/*Cn"

        /// 参与签名计算并通过请求头发送的固定随机串。
        static let nonce = "4ce7a7aa759b40f794d189a88b84aba8"

        /// 响应内容协商使用的哔咔 JSON Media Type。
        static let accept = "application/vnd.picacomic.com.v1+json"

        /// 哔咔 Android API 协议使用的固定 okhttp User-Agent。
        static let userAgent = "okhttp/3.8.1"

        /// 客户端构建版本，作为协议请求头发送。
        static let appBuildVersion = "45"

        /// 客户端平台标识，沿用哔咔协议要求的 Android 值。
        static let appPlatform = "android"

        /// 客户端实例标识，沿用旧客户端协议中的固定值。
        static let appUUID = "defaultUuid"

        /// 客户端版本，作为协议请求头发送。
        static let appVersion = "2.2.1.3.3.4"

        /// 客户端渠道标识，作为协议请求头发送。
        static let appChannel = "1"
    }

    /// 哔咔业务 API 的固定 Base URL（不含动态线路选择）。
    enum Host {
        /// 首次使用和旧自动偏好统一选择的默认 API Base URL。
        static let defaultBaseURL = URL(string: "https://picaapi.go2778.com/")!

        /// 用户仍可手动选择的官方 API Base URL。
        static let officialBaseURL = URL(string: "https://picaapi.picacomic.com/")!

        /// 设置页展示的线路名：第一个是第三方中转，第二个是官方直连。
        static let defaultBaseURLTitle = "CDN中转"
        static let officialBaseURLTitle = "官方直连"

        /// 按默认、官方顺序返回全部内置候选（地址＋展示名）。
        static let orderedCandidates = [
            SourceHostCandidate(baseURL: defaultBaseURL, title: defaultBaseURLTitle),
            SourceHostCandidate(baseURL: officialBaseURL, title: officialBaseURLTitle),
        ]
    }

    /// 官方推荐之外的独立个性化推荐服务；请求不携带哔咔 API 凭证。
    enum Recommendation {
        static let baseURL = URL(string: "https://macapi1.com/picacomic/rec/")!
        static let requestLimit = 10
        static let maximumHydrationConcurrency = 3
    }

    /// 哔咔本地持久化 Key；Bundle Identifier 前缀由 `AppIdentifierNamespace` 生成，
    /// 版本段写在各 key 字符串里。
    enum Storage {
        /// 上次验证成功后用于页面展示的非敏感账号资料。
        static let accountProfile = AppIdentifierNamespace.make("v1.account-profile.bika")

        /// 非阅读页面当前使用的图片质量。
        static let browsingImageQuality = AppIdentifierNamespace.make("v1.image-quality.bika")

        /// 图片请求是否使用 go2778 CDN 加速。
        static let usesImageCDNAcceleration = AppIdentifierNamespace.make("v1.image-cdn-acceleration.bika")

        /// 个性化推荐追踪中上一个成功展示的作品 ID。
        ///
        /// 个性化推荐没有开关、始终启用（2026-09-24 开发者决定），因此这里只保存跳转起点，
        /// 供推荐跳转上报（`from_id`）使用。
        static let personalizedRecommendationOrigin = AppIdentifierNamespace.make(
            "v1.personalized-recommendation-origin.bika",
        )
    }
}

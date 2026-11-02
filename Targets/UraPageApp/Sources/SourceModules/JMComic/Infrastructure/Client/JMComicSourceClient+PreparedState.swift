import Alamofire
import Foundation

/// 保存禁漫当前业务 Session 和与其配套的远程 Setting。
struct JMComicPreparedState: SourceSessionPreparedState {
    /// 创建 Session 时绑定的 API 地址。
    let baseURL: URL

    /// 已经安装禁漫请求拦截器的业务 Session。
    let session: Session

    /// 业务请求和图片请求共同依赖的远程配置。
    let setting: JMComicRemoteSetting
}

extension JMComicSourceClient {
    /// 获取 Base URL、创建签名 Session，并在加载远程 Setting 后组成可用状态。
    static func makePreparedState(
        hostProvider: SourceHostProvider,
        sourcePreferences: JMComicSourcePreferences,
        access: JMComicAccountAccessStore,
    ) async throws -> JMComicPreparedState {
        // Host 解析与 User-Agent 准备互不依赖，同时执行以缩短首次准备时间。
        async let resolvedBaseURL = hostProvider.baseURL()
        async let resolvedUserAgent = SourceUserAgentProvider.shared.userAgent(for: .android)
        let (baseURL, userAgent) = try await (resolvedBaseURL, resolvedUserAgent)

        let imageSourceKey = storedImageSourceKey()
        let credential = try await access.credentialForSession()
        let session = makeSession(
            baseURL: baseURL,
            userAgent: userAgent,
            sourcePreferences: sourcePreferences,
            credential: credential,
        )

        // 禁漫业务接口依赖远程 Setting，Session 只有在 Setting 成功后才算准备完成。
        let setting = try await fetchRemoteSetting(using: session, imageSourceKey: imageSourceKey)
        storeImageSourceKey(setting.selectedImageSourceKey)

        return JMComicPreparedState(baseURL: baseURL, session: session, setting: setting)
    }

    /// 创建绑定 Base URL、User-Agent 并共享进程内语言值的禁漫 Session。
    private static func makeSession(
        baseURL: URL,
        userAgent: String,
        sourcePreferences: JMComicSourcePreferences,
        credential: JMComicCredential?,
    ) -> Session {
        let configuration = URLSessionConfiguration.af.default
        SourceConfiguration.Session.applyDefaults(to: configuration)

        // AVS 由登录响应与请求拦截器明确管理，不允许 URLSession 额外保存隐式 Cookie。
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil

        return Session(
            configuration: configuration,
            interceptor: JMComicRequestInterceptor(
                baseURL: baseURL,
                userAgent: userAgent,
                sourcePreferences: sourcePreferences,
                credential: credential,
            ),
        )
    }

    /// 把 Client 内部 Setting 转换为来源设置页面需要的最小公开快照。
    static func imageSourceSelectionSnapshot(from setting: JMComicRemoteSetting)
        -> JMComicImageSourceSelectionSnapshot {
        JMComicImageSourceSelectionSnapshot(
            imageSources: setting.imageSources,
            selectedKey: setting.selectedImageSourceKey,
            activeImageHost: setting.imageHost,
        )
    }

    /// 读取上次确认的图源 Key；缺失或无效时恢复协议默认值。
    private static func storedImageSourceKey() -> Int {
        let key: Int? = UserDefaults.standard.storedValue(forKey: JMComicConfiguration.Storage.imageSource)
        guard let key, key > 0 else {
            UserDefaults.standard.removeObject(forKey: JMComicConfiguration.Storage.imageSource)
            return JMComicConfiguration.API.defaultImageSourceKey
        }

        return key
    }

    /// 保存已经由远程 Setting 确认存在的图源 Key。
    static func storeImageSourceKey(_ key: Int) {
        UserDefaults.standard.set(key, forKey: JMComicConfiguration.Storage.imageSource)
    }
}

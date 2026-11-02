import Alamofire
import Foundation

/// 保存绅士业务请求共同使用的 Base URL、Session 和 User-Agent。
struct ShenshiPreparedState: SourceSessionPreparedState {
    /// 创建 Session 时绑定的网页地址。
    let baseURL: URL

    /// 已经安装绅士请求拦截器的业务 Session。
    let session: Session

    /// HTML 与图片请求共同使用的移动端 User-Agent。
    let userAgent: String
}

/// 持有绅士当前业务 Session，并提供按能力拆分的请求环境。
///
/// 准备状态机由公共 `SourceClientState` 承担；Session 从 Keychain 恢复网页登录 Cookie。
actor ShenshiSourceClient: SourceAuthenticatedClient {
    let hostProvider: SourceHostProvider

    let clientState: SourceClientState<ShenshiPreparedState>

    /// 串行执行 Host 变更，并让读取等待在途变更结束。
    let hostOperations = SourceHostOperationRunner()

    /// 认证失效收口：服务端明确拒绝认证时通知账号 owner 清理凭证。
    let authentication: SourceAuthenticationHandler

    @MainActor
    init(
        hostProvider: SourceHostProvider,
        access: ShenshiAccountAccessStore,
    ) {
        self.hostProvider = hostProvider
        authentication = SourceAuthenticationHandler(access: access)

        // 准备闭包直接捕获构造参数，既不引用尚未完成初始化的 self，也不为此多存一份属性。
        clientState = SourceClientState {
            try await ShenshiSourceClient.makePreparedState(
                hostProvider: hostProvider,
                access: access,
            )
        }
    }

    /// 并行准备 Host 与 User-Agent，再创建绑定本次进程地址的 Session。
    private static func makePreparedState(
        hostProvider: SourceHostProvider,
        access: ShenshiAccountAccessStore,
    ) async throws -> ShenshiPreparedState {
        // Host 解析与 UA 生成互不依赖，并行执行以缩短首次准备时间。
        async let resolvedBaseURL = hostProvider.baseURL()
        async let resolvedUserAgent = SourceUserAgentProvider.shared.userAgent(for: .iOS)
        let (baseURL, userAgent) = try await (resolvedBaseURL, resolvedUserAgent)
        let credential = try await access.credentialForSession()

        return ShenshiPreparedState(
            baseURL: baseURL,
            session: makeSession(baseURL: baseURL, userAgent: userAgent, credential: credential),
            userAgent: userAgent,
        )
    }

    /// 创建绑定当前 Base URL 的绅士 Session；User-Agent 与会话 Cookie 由拦截器按请求附加。
    ///
    /// 配置里不再放任何协议头：凭证是创建时的快照，换凭证后由 `credentialDidChange()` 重建 Session。
    static func makeSession(
        baseURL: URL,
        userAgent: String,
        credential: ShenshiCredential?,
    ) -> Session {
        let configuration = URLSessionConfiguration.af.ephemeral
        SourceConfiguration.Session.applyCookieFreeDefaults(to: configuration)

        return Session(
            configuration: configuration,
            interceptor: ShenshiRequestInterceptor(
                baseURL: baseURL,
                userAgent: userAgent,
                credential: credential,
            ),
        )
    }
}

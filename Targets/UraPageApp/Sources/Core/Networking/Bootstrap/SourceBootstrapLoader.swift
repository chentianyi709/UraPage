import Alamofire
import Foundation

/// 使用独立无状态 Session，为来源读取固定 Host bootstrap 的原始数据。
///
/// 只接受代码内置 URL；不解析 JSON、HTML、密文或业务 Host。
/// 不与业务 Session 共用认证、签名、Cookie 或缓存，也不用于列表、详情、登录和图片 API。
struct SourceBootstrapLoader: Sendable {
    /// 进程级共享传输器：不包含来源账号、Host 选择或页面状态。
    static let shared = SourceBootstrapLoader()

    private let session = SourceBootstrapLoader.makeSession()

    /// 创建拒绝重定向、禁用 Cookie 与响应缓存的共享 Loader。
    private init() {}

    /// 创建一次性配置的无状态 Session；不与业务 Session 共享认证、Cookie 与缓存。
    private static func makeSession() -> Session {
        let configuration = URLSessionConfiguration.ephemeral
        SourceConfiguration.Session.applyCookieFreeDefaults(to: configuration)
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData

        return Session(
            configuration: configuration,
            redirectHandler: Redirector(behavior: .doNotFollow),
        )
    }

    /// 读取一份固定 bootstrap 资源。
    ///
    /// - Throws: HTTP 非成功或空响应抛出 `ComicSourceError.invalidResponse`；
    ///   取消保持 `CancellationError`。
    func data(from url: URL) async throws -> Data {
        let data = try await session
            .request(URLRequest(url: url))
            .validate(statusCode: 200 ..< 300)
            .serializingData()
            .value

        guard !data.isEmpty else {
            throw ComicSourceError.invalidResponse
        }

        return data
    }
}

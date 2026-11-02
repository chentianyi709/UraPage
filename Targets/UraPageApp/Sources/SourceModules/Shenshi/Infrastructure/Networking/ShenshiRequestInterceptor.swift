import Alamofire
import Foundation

/// 为绑定一个 Base URL 的绅士 Session 补全完整地址，并携带来源协议头。
///
/// 凭证与 User-Agent 都是 Session 创建时的快照（与 Bika／JM 同形）：换凭证后必须重建 Session，
/// 由 `ShenshiSourceClient.credentialDidChange()` 触发。协议头只在请求未显式设置时写入，
/// 调用方显式给出的值优先（登录请求自带 `Referer`／`Content-Type`，章节脚本自带 `User-Agent`）。
/// 重试语义由 `SourceRetryingRequestInterceptor` 统一提供。
final class ShenshiRequestInterceptor: SourceRetryingRequestInterceptor, Sendable {
    private let baseURL: URL

    /// 本 Session 使用的移动端 User-Agent。
    private let userAgent: String

    /// 登录后的会话 Cookie；未登录为 `nil`。
    private let credential: ShenshiCredential?

    init(baseURL: URL, userAgent: String, credential: ShenshiCredential?) {
        self.baseURL = baseURL
        self.userAgent = userAgent
        self.credential = credential
    }

    /// 保留完整地址，补全相对路径，并按需附加 User-Agent 与会话 Cookie。
    func adapt(
        _ urlRequest: URLRequest,
        for _: Session,
        completion: @escaping @Sendable (Result<URLRequest, any Error>) -> Void,
    ) {
        do {
            var request = urlRequest
            // 相对路径补全为完整地址；已是完整地址（如 Reader 脚本地址）时保持原样。
            if request.url?.host == nil {
                guard let absoluteURL = SourceRelativeURL.absolute(request.url, base: baseURL) else {
                    throw ShenshiAPIError.invalidRequest
                }

                request.url = absoluteURL
            }

            // 默认头只在调用方未显式设置时写入，避免覆盖来源协议要求的特定值。
            if request.value(forHTTPHeaderField: "User-Agent") == nil {
                request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
            }
            if let credential, request.value(forHTTPHeaderField: "Cookie") == nil {
                request.setValue(credential.cookieHeader, forHTTPHeaderField: "Cookie")
            }

            completion(.success(request))
        } catch {
            completion(.failure(error))
        }
    }
}

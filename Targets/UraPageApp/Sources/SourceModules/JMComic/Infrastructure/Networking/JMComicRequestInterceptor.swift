import Alamofire
import Foundation

/// 为一个已经选定 Base URL 的禁漫 Session 拼接接口路径并添加公共签名 Header。
///
/// 只负责请求适配；重试语义由 `SourceRetryingRequestInterceptor` 统一提供。
/// 不持有 Session，也不处理业务响应。
///
/// 签名材料（时间戳、`Tokenparam`、`Token`）与网页端一致：**一个 Session 只算一次**，
/// 同一 Session 内的请求与重试复用同一份签名；Host／凭证变化会重建 Session，从而重新生成。
final class JMComicRequestInterceptor: SourceRetryingRequestInterceptor, Sendable {
    private let baseURL: URL
    private let userAgent: String
    private let sourcePreferences: JMComicSourcePreferences
    private let credential: JMComicCredential?

    /// 本 Session 固定的签名材料。
    private let tokenParam: String
    private let token: String

    init(
        baseURL: URL,
        userAgent: String,
        sourcePreferences: JMComicSourcePreferences,
        credential: JMComicCredential?,
    ) {
        self.baseURL = baseURL
        self.userAgent = userAgent
        self.sourcePreferences = sourcePreferences
        self.credential = credential

        let timestamp = Int(Date().timeIntervalSince1970)
        tokenParam = "\(timestamp),\(JMComicConfiguration.API.appVersion)"
        token = JMComicConfiguration.API.token(for: timestamp)
    }

    /// 将相对接口路径转换为完整 URL，并为请求添加 JM 公共 Header。
    func adapt(
        _ urlRequest: URLRequest,
        for _: Session,
        completion: @escaping @Sendable (Result<URLRequest, any Error>) -> Void,
    ) {
        do {
            var request = urlRequest

            // 相对路径补全为完整地址；已是完整地址（含 host）时保持原样。
            if request.url?.host == nil {
                guard let absoluteURL = SourceRelativeURL.absolute(request.url, base: baseURL) else {
                    throw JMComicAPIError.invalidURL
                }

                request.url = absoluteURL
            }

            // 所有 GET 接口统一使用用户当前选择的内容语言；请求自带 lang 时不覆盖（与网页端一致）。
            if request.httpMethod == HTTPMethod.get.rawValue {
                guard let url = request.url else {
                    throw JMComicAPIError.invalidURL
                }

                let hasLanguage = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                    .queryItems?
                    .contains { $0.name == "lang" } ?? false
                if !hasLanguage {
                    request.url = url.appending(
                        queryItems: [
                            URLQueryItem(name: "lang", value: sourcePreferences.contentLanguage().rawValue),
                        ],
                    )
                }
            }

            // 固定签名 Header：本 Session 的时间戳 + 版本、对应的 Token、User-Agent。
            request.setValue(tokenParam, forHTTPHeaderField: "Tokenparam")
            request.setValue(token, forHTTPHeaderField: "Token")
            request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

            // 登录后的所有业务请求携带当前 Session 创建时绑定的认证信息。
            if let credential {
                request.setValue("Bearer \(credential.jwtToken)", forHTTPHeaderField: "Authorization")
                request.setValue("AVS=\(credential.sessionValue)", forHTTPHeaderField: "Cookie")
            }

            completion(.success(request))
        } catch {
            completion(.failure(error))
        }
    }
}

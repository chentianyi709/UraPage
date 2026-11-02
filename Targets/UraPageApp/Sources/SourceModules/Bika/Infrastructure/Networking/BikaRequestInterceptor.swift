import Alamofire
import Foundation

/// 为绑定一个 Base URL 的哔咔 Session 拼接地址并生成每次请求的协议签名。
///
/// 只负责请求适配；重试语义由 `SourceRetryingRequestInterceptor` 统一提供，
/// 相对地址拼接复用公共工具，签名算法复用 `BikaHMACSignature`，拦截器自身不持有 Session。
final class BikaRequestInterceptor: SourceRetryingRequestInterceptor, Sendable {
    private let baseURL: URL
    private let credential: BikaCredential?
    private let sourcePreferences: BikaSourcePreferences

    init(
        baseURL: URL,
        credential: BikaCredential?,
        sourcePreferences: BikaSourcePreferences,
    ) {
        self.baseURL = baseURL
        self.credential = credential
        self.sourcePreferences = sourcePreferences
    }

    /// 将相对请求转换为完整 URL，再基于最终 path 与 query 添加固定请求头与签名。
    func adapt(
        _ urlRequest: URLRequest,
        for _: Session,
        completion: @escaping @Sendable (Result<URLRequest, any Error>) -> Void,
    ) {
        do {
            try completion(.success(adaptedRequest(urlRequest)))
        } catch {
            completion(.failure(error))
        }
    }

    /// 补全来源相对路径并签名，供哔咔前台业务 Session 发送。
    func adaptedRequest(_ urlRequest: URLRequest) throws -> URLRequest {
        var request = urlRequest
        // 相对路径补全为完整地址；已是完整地址时保持原样。
        if request.url?.host == nil {
            guard let absoluteURL = SourceRelativeURL.absolute(request.url, base: baseURL) else {
                throw BikaAPIError.invalidRequest
            }

            request.url = absoluteURL
        }

        guard let url = request.url,
              let method = request.httpMethod,
              !method.isEmpty
        else {
            throw BikaAPIError.invalidRequest
        }

        // 签名基于“去掉开头斜杠、保留百分号编码 query”的最终路径。
        let timestamp = String(Int(Date().timeIntervalSince1970))
        let requestPath = try Self.signaturePath(for: url)

        request.setValue(BikaConfiguration.API.accept, forHTTPHeaderField: "accept")
        request.setValue(BikaConfiguration.API.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.setValue(BikaConfiguration.API.apiKey, forHTTPHeaderField: "api-key")
        request.setValue(BikaConfiguration.API.appBuildVersion, forHTTPHeaderField: "app-build-version")
        request.setValue(BikaConfiguration.API.appPlatform, forHTTPHeaderField: "app-platform")
        request.setValue(BikaConfiguration.API.appUUID, forHTTPHeaderField: "app-uuid")
        request.setValue(BikaConfiguration.API.appVersion, forHTTPHeaderField: "app-version")
        request.setValue(BikaConfiguration.API.nonce, forHTTPHeaderField: "nonce")
        request.setValue(BikaConfiguration.API.appChannel, forHTTPHeaderField: "app-channel")

        let imageQuality = request.value(forHTTPHeaderField: "image-quality")
            ?? sourcePreferences.browsingImageQuality().rawValue
        request.setValue(imageQuality, forHTTPHeaderField: "image-quality")
        request.setValue(timestamp, forHTTPHeaderField: "time")
        request.setValue(
            BikaHMACSignature.make(requestPath: requestPath, timestamp: timestamp, method: method),
            forHTTPHeaderField: "signature",
        )

        if let credential {
            request.setValue(credential.token, forHTTPHeaderField: "authorization")
        }

        return request
    }

    /// 生成不含开头斜杠、但保留原始百分号编码 query 的签名路径。
    ///
    /// 签名算法要求路径不含起始 `/`，且查询参数必须用原始编码参与计算，
    /// 因此这里解码为组件后再取 percentEncodedPath/Query，而不是用 URL.path。
    private static func signaturePath(for url: URL) throws -> String {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw BikaAPIError.invalidRequest
        }

        let path = String(components.percentEncodedPath.drop(while: { $0 == "/" }))
        guard !path.isEmpty else {
            throw BikaAPIError.invalidRequest
        }
        guard let query = components.percentEncodedQuery, !query.isEmpty else {
            return path
        }

        return "\(path)?\(query)"
    }
}

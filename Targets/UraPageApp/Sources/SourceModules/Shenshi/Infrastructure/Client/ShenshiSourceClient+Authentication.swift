import Alamofire
import Foundation

extension ShenshiSourceClient {
    /// 按移动网页协议登录，并用返回的 Cookie 读取资料页验证会话。
    ///
    /// 登录使用独立的无凭证 Session，避免失败尝试污染当前已认证会话；只有登录响应成功、
    /// Cookie 可解析且资料页可读取后，才把结果交给账号 owner 持久化。
    func signIn(username: String, password: String) async throws
        -> SourceAuthenticationResult<ShenshiCredential, ShenshiAccountProfile> {
        let state = try await preparedState()
        let candidateSession = Self.makeSession(
            baseURL: state.baseURL,
            userAgent: state.userAgent,
            credential: nil,
        )

        let loginURL = state.baseURL.appendingPathComponent("users-login.html")
        let response = await candidateSession
            .request(
                "/users-check_login.html",
                method: .post,
                parameters: [
                    "normal": "",
                    "remember_pass": "",
                    "login_name": username,
                    "login_pass": password,
                ],
                encoding: URLEncoding.default,
                headers: [
                    HTTPHeader(name: "X-Requested-With", value: "XMLHttpRequest"),
                    HTTPHeader(name: "Accept", value: "application/json, text/javascript, */*; q=0.01"),
                    HTTPHeader(name: "Referer", value: loginURL.absoluteString),
                    HTTPHeader(
                        name: "Content-Type",
                        value: "application/x-www-form-urlencoded; charset=UTF-8",
                    ),
                ],
            )
            .validate(statusCode: 200 ..< 300)
            .serializingData()
            .response

        let data = try response.result.get()
        let login = try JSONDecoder().decode(ShenshiLoginDTO.self, from: data)
        guard login.ret else {
            throw ShenshiAPIError.authenticationRejected
        }
        guard let httpResponse = response.response else {
            throw ShenshiAPIError.invalidResponse
        }

        let credential = try Self.credential(from: httpResponse, responseURL: loginURL)
        let authenticatedSession = Self.makeSession(
            baseURL: state.baseURL,
            userAgent: state.userAgent,
            credential: credential,
        )
        let profile = try await authenticatedSession
            .request("/users-profile.html", method: .get)
            .shenshiParsedTextResponse { html in
                try ShenshiAccountProfileHTMLParser.parse(html, username: username)
            }

        return SourceAuthenticationResult(credential: credential, profile: profile)
    }

    /// 从网页登录响应生成后续请求使用的 Cookie header；Cookie 名由响应决定，不硬编码。
    private static func credential(
        from response: HTTPURLResponse,
        responseURL: URL,
    ) throws -> ShenshiCredential {
        let headerFields = response.allHeaderFields.reduce(into: [String: String]()) { fields, entry in
            guard let name = entry.key as? String, let value = entry.value as? String else {
                return
            }

            fields[name] = value
        }
        let cookies = HTTPCookie.cookies(withResponseHeaderFields: headerFields, for: responseURL)
        let cookieHeader = cookies
            .sorted { $0.name < $1.name }
            .map { "\($0.name)=\($0.value)" }
            .joined(separator: "; ")

        guard !cookieHeader.isEmpty else {
            throw ShenshiAPIError.invalidResponse
        }

        return ShenshiCredential(cookieHeader: cookieHeader)
    }
}

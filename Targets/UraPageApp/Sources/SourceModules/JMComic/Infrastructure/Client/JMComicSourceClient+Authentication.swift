import Alamofire
import Foundation

extension JMComicSourceClient {
    /// 登录禁漫账号：只请求并解析凭证与展示资料，不落盘、不发布登录状态。
    ///
    /// 落盘与发布由账号 owner（`JMComicAccount`）负责，Client 不直接写 Keychain（与哔咔同一分层）。
    /// 登录接口用外层业务码 401 表示账号或密码错误，在这里转成公共的「需要认证」语义，
    /// 公共登录页就不必认识禁漫的业务码。
    func login(username: String, password: String) async throws -> JMComicLoginDTO {
        do {
            return try await readIgnoringAuthenticationRejection { preparedState in
                try await preparedState.session
                    .request(
                        "/login",
                        method: .post,
                        parameters: [
                            "username": username,
                            "password": password,
                            "t": Int(Date().timeIntervalSince1970),
                        ],
                        encoding: URLEncoding.default,
                    )
                    .jmComicDecodedResponse(as: JMComicLoginDTO.self)
            }
        } catch let JMComicAPIError.serverRejected(code, _) where code == 401 {
            throw ComicSourceError.authenticationRequired
        }
    }
}

import Alamofire
import Foundation

extension JMComicSourceClient {
    /// 登录禁漫账号：只请求并解析凭证与展示资料，不落盘、不发布登录状态。
    ///
    /// 落盘与发布由账号 owner（`JMComicAccount`）负责，Client 不直接写 Keychain（与哔咔同一分层）。
    func login(username: String, password: String) async throws -> JMComicLoginDTO {
        try await readIgnoringAuthenticationRejection { preparedState in
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
    }
}

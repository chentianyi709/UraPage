import Alamofire
import Foundation

extension BikaSourceClient {
    /// 登录哔咔账号：只提交邮箱密码换取 Token，不验证、不落盘。
    func signIn(email: String, password: String) async throws -> BikaCredential {
        let response = try await readIgnoringAuthenticationRejection { state in
            try await state.session
                .request(
                    "auth/sign-in",
                    method: .post,
                    parameters: ["email": email, "password": password],
                    encoding: JSONEncoding.default,
                )
                .bikaLoginDecodedResponse(as: BikaLoginDTO.self)
        }

        // 没有 Token 的“成功”响应无法用于后续请求，按无效响应处理。
        guard !response.token.isEmpty else {
            throw BikaAPIError.invalidResponse
        }

        return BikaCredential(token: response.token)
    }

    /// 用候选 Token 请求 `users/profile`：既是登录验证，也取得账号资料（验证通过才由账号 owner 落盘）。
    ///
    /// 这里用候选 Token 单独建一个临时 Session：既不把未验证的 Token 写进 Keychain，
    /// 也不让旧的（可能已失效的）凭证被拦截器带上。
    func accountProfile(using credential: BikaCredential) async throws -> BikaAccountProfile {
        let preparedState = try await preparedState()
        let candidateSession = BikaSourceClient.makeSession(
            baseURL: preparedState.baseURL,
            credential: credential,
            sourcePreferences: sourcePreferences,
        )

        let response = try await candidateSession
            .request("users/profile", method: .get)
            .bikaDecodedResponse(as: BikaUserProfileDTO.self)

        return response.user.accountProfile
    }
}

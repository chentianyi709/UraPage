import Foundation

/// 哔咔账号 owner：公共 `SourceAccount` 绑定本源凭证、资料与 Client。
///
/// 登录顺序与旧版一致：先用邮箱密码换 Token，再用候选 Token 请求 `users/profile` 验证，
/// **验证通过才落盘**；随后让旧 Session 失效，使下次请求带新 Token 重建。
/// 访问事实与 Client 的 401 收口共享同一实例（`BikaServices` 注入）。
typealias BikaAccount = SourceAccount<BikaCredential, BikaAccountProfile>

extension SourceAccount where Credential == BikaCredential, Profile == BikaAccountProfile {
    /// 哔咔账号 owner：使用本源资料 key，并在凭证变化后让旧 Session 失效。
    convenience init(client: BikaSourceClient, access: BikaAccountAccessStore) {
        self.init(
            access: access,
            storageKey: BikaConfiguration.Storage.accountProfile,
            credentialDidChange: { await client.credentialDidChange() },
            requestLogin: { email, password in
                let credential: BikaCredential
                do {
                    credential = try await client.signIn(email: email, password: password)
                } catch let BikaAPIError.serverRejected(code) where code == 400 {
                    // 哔咔用业务码 400 表示「账号或密码错误」：转成公共的「凭证不成立」，
                    // 让公共登录界面给出可操作文案，不把来源业务码泄漏到页面。
                    throw ComicSourceError.authenticationRequired
                }

                return try await SourceAuthenticationResult(
                    credential: credential,
                    profile: client.accountProfile(using: credential),
                )
            },
        )
    }
}

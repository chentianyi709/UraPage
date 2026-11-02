import Foundation

/// 禁漫账号 owner：公共 `SourceAccount` 绑定本源凭证、资料与 Client。
///
/// 登录请求在便利构造里给出：`/login` 直接返回凭证与展示资料，无需二次验证。
/// 访问事实与 Client 的 401 收口共享同一实例（`JMComicServices` 注入）。
typealias JMComicAccount = SourceAccount<JMComicCredential, JMComicAccountProfile>

extension SourceAccount where Credential == JMComicCredential, Profile == JMComicAccountProfile {
    /// 禁漫账号 owner：使用本源资料 key，并在凭证变化后让旧 Session 失效。
    convenience init(client: JMComicSourceClient, access: JMComicAccountAccessStore) {
        self.init(
            access: access,
            storageKey: JMComicConfiguration.Storage.accountProfile,
            credentialDidChange: { await client.credentialDidChange() },
            requestLogin: { username, password in
                let response = try await client.login(username: username, password: password)
                return SourceAuthenticationResult(
                    credential: response.credential,
                    profile: response.accountProfile,
                )
            },
        )
    }
}

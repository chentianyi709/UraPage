import Foundation

/// 绅士账号 owner：公共 `SourceAccount` 绑定本源凭证、资料与 Client。
///
/// 登录请求在便利构造里给出：按移动网页协议提交表单、解析 `Set-Cookie`，并用候选 Cookie
/// 读取资料页验证（验证通过才落盘）。访问事实与 Client 的 401 收口共享同一实例。
typealias ShenshiAccount = SourceAccount<ShenshiCredential, ShenshiAccountProfile>

extension SourceAccount where Credential == ShenshiCredential, Profile == ShenshiAccountProfile {
    /// 绅士账号 owner：使用本源资料 key，并在凭证变化后让旧 Session 失效。
    convenience init(client: ShenshiSourceClient, access: ShenshiAccountAccessStore) {
        self.init(
            access: access,
            storageKey: ShenshiConfiguration.Storage.accountProfile,
            credentialDidChange: { await client.credentialDidChange() },
            requestLogin: { username, password in
                let result = try await client.signIn(username: username, password: password)
                return SourceAuthenticationResult(credential: result.credential, profile: result.profile)
            },
        )
    }
}

import Foundation

/// 保存绅士后续认证请求需要的会话 Cookie。
///
/// 网页登录成功后通过 `Set-Cookie` 返回认证信息，Cookie 名带服务端生成的后缀，不能硬编码；
/// 因此凭证保存由响应生成的完整 `Cookie` 请求头，并只在绅士 Session 内使用。
struct ShenshiCredential: Codable, Sendable {
    let cookieHeader: String
}

extension SourceCredentialRecord where Value == ShenshiCredential {
    /// 绅士凭证记录。
    static var shenshi: Self {
        Self(sourceID: .shenshi)
    }
}

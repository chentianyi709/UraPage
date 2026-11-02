import Foundation

/// 哔咔账号资料（非敏感，持久化在 `BikaConfiguration.Storage.accountProfile`）。
///
/// 只保留页面展示需要的字段；Token 与访问事实由 `BikaAccountAccessStore` 与 `BikaCredential` 负责。
struct BikaAccountProfile: Codable, Sendable, Equatable {
    /// 服务端用户 ID（`_id`）。
    let accountID: String

    /// 登录邮箱。
    let email: String

    /// 昵称（服务端 `name`）；可能为空。
    let nickname: String

    /// 页面展示名：昵称为空时回落到邮箱。
    var displayName: String {
        nickname.isEmpty ? email : nickname
    }
}

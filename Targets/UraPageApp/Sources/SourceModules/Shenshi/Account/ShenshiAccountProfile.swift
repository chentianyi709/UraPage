import Foundation

/// 绅士账号资料（非敏感，持久化在 `ShenshiConfiguration.Storage.accountProfile`）。
///
/// 登录成功后从网页资料页读取；该页面当前只提供登录名与昵称，没有可靠的用户 ID。
struct ShenshiAccountProfile: Codable, Sendable, Equatable {
    /// 登录账号名。
    let username: String

    /// 资料页中的昵称。
    let displayName: String
}

import Foundation

/// 禁漫账号资料（非敏感，持久化在 `JMComicConfiguration.Storage.accountProfile`）。
///
/// 只保留页面展示需要的字段；凭证与访问事实由 `JMComicAccountAccessStore` 与 `JMComicCredential` 负责。
struct JMComicAccountProfile: Codable, Sendable, Equatable {
    /// 服务端用户 ID（`uid`）；退出后用于区分本地数据归属。
    let accountID: String

    /// 登录账号名。
    let username: String

    /// 展示名称（登录响应 `fname`）；服务端未给出时回落到账号名。
    let displayName: String

    /// 数字等级。
    let level: Int

    /// 服务端等级名称；为空时只展示数字等级。
    let levelName: String

    /// 头像引用；服务端未给出头像时为 `nil`（页面显示占位图标）。
    let avatar: ComicImageReference?

    /// 等级展示文本：有等级名称时一并展示。
    var levelText: String {
        levelName.isEmpty ? "Lv.\(level)" : "\(levelName) · Lv.\(level)"
    }
}

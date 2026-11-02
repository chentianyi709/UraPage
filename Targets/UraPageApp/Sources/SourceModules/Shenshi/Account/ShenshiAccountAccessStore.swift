import Foundation

/// 绅士账号访问 owner：公共 `SourceAccountAccessStore` 绑定本源凭证类型、Keychain 记录与日志分类。
///
/// 保存／恢复凭证、发布访问事实、退出与认证失效清理的行为都在公共实现里；
/// 本源只声明凭证类型与存放位置。
typealias ShenshiAccountAccessStore = SourceAccountAccessStore<ShenshiCredential>

extension SourceAccountAccessStore where Credential == ShenshiCredential {
    /// 绅士账号 owner：使用本源 Keychain 记录与日志分类。
    convenience init() {
        self.init(credentials: .shenshi, logCategory: "Shenshi.Account")
    }
}

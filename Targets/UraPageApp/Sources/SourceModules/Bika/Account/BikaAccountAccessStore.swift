import Foundation

/// 哔咔账号访问 owner：公共 `SourceAccountAccessStore` 绑定本源凭证类型、Keychain 记录与日志分类。
///
/// 保存／恢复凭证、发布访问事实、认证失效（401）清理的行为都在公共实现里；
/// 本源只声明凭证类型与存放位置。
typealias BikaAccountAccessStore = SourceAccountAccessStore<BikaCredential>

extension SourceAccountAccessStore where Credential == BikaCredential {
    /// 哔咔账号 owner：使用本源 Keychain 记录与日志分类。
    convenience init() {
        self.init(credentials: .bika, logCategory: "Bika.Account")
    }
}

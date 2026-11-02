import Foundation

/// 禁漫账号访问 owner：公共 `SourceAccountAccessStore` 绑定本源凭证类型、Keychain 记录与日志分类。
///
/// 保存／恢复凭证、发布访问事实、退出与认证失效（401）清理的行为都在公共实现里；
/// 本源只声明凭证类型与存放位置。
typealias JMComicAccountAccessStore = SourceAccountAccessStore<JMComicCredential>

extension SourceAccountAccessStore where Credential == JMComicCredential {
    /// 禁漫账号 owner：使用本源 Keychain 记录与日志分类。
    convenience init() {
        self.init(credentials: .jm, logCategory: "JM.Account")
    }
}

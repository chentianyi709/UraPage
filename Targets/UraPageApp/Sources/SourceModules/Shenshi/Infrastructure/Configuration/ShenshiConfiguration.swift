import Foundation

/// 绅士来源的固定协议常量与持久化标识符。
///
/// 绅士当前只有 Host 发布页与账号资料 key；可变状态与远端响应由各自 owner 管理。
enum ShenshiConfiguration {
    /// Host 发布页的固定尝试顺序。
    enum Host {
        /// 用于发现当前业务 Host；前一个失败后才会尝试下一个。
        static let bootstrapURLs = [
            URL(string: "https://wnacg01.link/")!,
            URL(string: "https://wnlink.ru/")!,
            URL(string: "https://wnacg02.link/")!,
        ]
    }

    /// 绅士本地持久化 Key；Bundle Identifier 前缀由 `AppIdentifierNamespace` 生成，
    /// 版本段写在各 key 字符串里。
    enum Storage {
        /// 上次登录成功后用于页面展示的非敏感账号资料。
        static let accountProfile = AppIdentifierNamespace.make("v1.account-profile.shenshi")
    }
}

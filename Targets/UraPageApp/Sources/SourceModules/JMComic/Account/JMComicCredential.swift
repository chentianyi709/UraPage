import Foundation

/// 保存禁漫后续认证请求需要的两个敏感字段。
struct JMComicCredential: Codable, Sendable {
    let jwtToken: String
    let sessionValue: String
}

extension SourceCredentialRecord where Value == JMComicCredential {
    /// 禁漫凭证记录。
    static var jm: Self {
        Self(sourceID: .jm)
    }
}

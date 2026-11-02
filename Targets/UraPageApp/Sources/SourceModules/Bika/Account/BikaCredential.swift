import Foundation

/// 保存哔咔后续认证请求需要的敏感 Token。
struct BikaCredential: Codable, Sendable {
    let token: String
}

extension SourceCredentialRecord where Value == BikaCredential {
    /// 哔咔凭证记录。
    static var bika: Self {
        Self(sourceID: .bika)
    }
}

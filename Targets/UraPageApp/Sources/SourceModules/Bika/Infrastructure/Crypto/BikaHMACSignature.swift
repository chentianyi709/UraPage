import CryptoKit
import Foundation

/// 计算哔咔 API 的 HMAC-SHA256 请求签名。
///
/// 签名输入为“最终百分号编码路径 + 时间戳 + nonce + 请求方法 + apiKey”的小写串；
/// 签名材料来自 `BikaConfiguration.API`，本类型只负责算法。
enum BikaHMACSignature {
    /// 生成小写十六进制签名，供请求拦截器写入 `signature` 头。
    static func make(requestPath: String, timestamp: String, method: String) -> String {
        let source = (
            requestPath
                + timestamp
                + BikaConfiguration.API.nonce
                + method
                + BikaConfiguration.API.apiKey,
        ).lowercased()

        let authenticationCode = HMAC<SHA256>.authenticationCode(
            for: Data(source.utf8),
            using: SymmetricKey(data: Data(BikaConfiguration.API.signatureSecret.utf8)),
        )
        return SourceDigest.hex(authenticationCode)
    }
}

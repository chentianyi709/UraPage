import Foundation

/// 把摘要字节序列格式化为小写十六进制字符串。
///
/// 供图片缓存 Key、来源签名和来源 Token 等复用，避免各处重复拼接
/// `String(format:)`。它不计算哈希本身，哈希算法与输入由调用方提供。
enum SourceDigest {
    /// 将摘要字节格式化为小写十六进制字符串。
    ///
    /// - Parameter bytes: 任意 `UInt8` 序列，例如 `SHA256Digest` 或 HMAC 认证码。
    static func hex(_ bytes: some Sequence<UInt8>) -> String {
        bytes.map { String(format: "%02x", $0) }.joined()
    }
}

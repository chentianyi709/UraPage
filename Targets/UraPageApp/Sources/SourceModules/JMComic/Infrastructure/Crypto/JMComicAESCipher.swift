import CommonCrypto
import Foundation

/// 执行禁漫 Host 与业务 API 响应共用的 AES-ECB 解密。
///
/// 只做算法，不含网络与业务语义；解密失败统一返回 `JMComicAPIError`，
/// 由上层边界转换为公共错误。
enum JMComicAESCipher {
    /// 按禁漫 API 的密钥顺序解密响应，返回有效的 JSON 数据。
    ///
    /// 依次尝试本次请求时间戳生成的两个密钥（主盐、备盐）；
    /// 只有解密结果能构成有效 JSON 才认为密钥匹配。
    static func decryptAPIResponse(_ base64Cipher: String, timestamp: Int) throws -> Data {
        // 漫画接口的响应密钥都由请求时间戳生成：主盐 + 备盐各一个。
        let keys = [
            JMComicConfiguration.API.token(for: timestamp),
            JMComicConfiguration.API.fallbackToken(for: timestamp),
        ]

        for key in keys {
            // 密钥不匹配时继续尝试下一个候选密钥。
            guard let decryptedData = try? decrypt(base64Cipher, key: key) else {
                continue
            }

            // AES 解密成功可能仍得到无意义字节，只有有效 JSON 才视为匹配。
            guard (try? JSONSerialization.jsonObject(with: decryptedData)) != nil else {
                continue
            }

            return decryptedData
        }

        throw JMComicAPIError.decryptionFailed
    }

    /// 解密 Base64 密文并返回去除 PKCS#7 padding 后的数据。
    static func decrypt(_ base64Cipher: String, key: String) throws -> Data {
        guard let cipherData = Data(base64Encoded: base64Cipher, options: .ignoreUnknownCharacters),
              !cipherData.isEmpty else {
            throw JMComicAPIError.decryptionFailed
        }

        let keyData = Data(key.utf8)
        guard [kCCKeySizeAES128, kCCKeySizeAES192, kCCKeySizeAES256].contains(keyData.count) else {
            throw JMComicAPIError.invalidConfiguration
        }

        let outputCapacity = cipherData.count + kCCBlockSizeAES128
        var output = Data(count: outputCapacity)
        var decryptedByteCount = 0

        let status = output.withUnsafeMutableBytes { outputBytes in
            cipherData.withUnsafeBytes { cipherBytes in
                keyData.withUnsafeBytes { keyBytes in
                    CCCrypt(
                        CCOperation(kCCDecrypt),
                        CCAlgorithm(kCCAlgorithmAES),
                        CCOptions(kCCOptionECBMode | kCCOptionPKCS7Padding),
                        keyBytes.baseAddress,
                        keyData.count,
                        nil,
                        cipherBytes.baseAddress,
                        cipherData.count,
                        outputBytes.baseAddress,
                        outputCapacity,
                        &decryptedByteCount,
                    )
                }
            }
        }

        guard status == kCCSuccess else {
            throw JMComicAPIError.decryptionFailed
        }

        output.removeSubrange(decryptedByteCount ..< output.count)
        return output
    }
}

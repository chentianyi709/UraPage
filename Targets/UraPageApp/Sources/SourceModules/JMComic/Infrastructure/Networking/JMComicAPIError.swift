/// 描述禁漫业务请求准备、响应包装和解密失败。
///
/// 这些错误只在本来源边界内使用；越过公开 Services 前必须经过
/// `SourceErrorMapper` 转换为安全的公共错误。
enum JMComicAPIError: Error, SourceDiagnosableError, SourcePublicErrorMapping {
    /// 调用方传入非法参数（程序错误），例如页码小于 0。
    case invalidArgument

    /// 本地签名或解密配置不可用，例如 AES 密钥长度不合法。
    case invalidConfiguration

    /// 请求缺少相对 URL，或无法与当前 Base URL 组合成有效地址。
    case invalidURL

    /// 服务端响应包装或解密后的 DTO 不符合预期格式。
    case invalidResponse

    /// HTTP 请求成功，但禁漫外层响应返回了非 200 业务码。
    case serverRejected(code: Int, message: String?)

    /// 响应包装中没有可用的加密 `data` 字段。
    case missingEncryptedData

    /// 响应密文无法使用当前候选密钥解密为有效 JSON。
    case decryptionFailed

    /// `/setting` 返回的必要配置无效，当前无法准备业务请求环境。
    case invalidSetting

    /// 日志用类别名；`serverRejected` 只保留安全数值码，不含服务端消息。
    var diagnosticName: String {
        switch self {
        case .invalidArgument:
            "invalidArgument"
        case .invalidConfiguration:
            "invalidConfiguration"
        case .invalidURL:
            "invalidURL"
        case .invalidResponse:
            "invalidResponse"
        case let .serverRejected(code, _):
            "serverRejected(\(code))"
        case .missingEncryptedData:
            "missingEncryptedData"
        case .decryptionFailed:
            "decryptionFailed"
        case .invalidSetting:
            "invalidSetting"
        }
    }

    /// 只保留安全的服务端业务码；其余 case 走协议默认映射收敛为 `invalidResponse`。
    var serverRejectionCode: Int? {
        switch self {
        case let .serverRejected(code, _):
            code
        default:
            nil
        }
    }
}

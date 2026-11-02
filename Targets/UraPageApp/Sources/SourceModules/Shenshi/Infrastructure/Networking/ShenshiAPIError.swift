/// 描述绅士请求构造与 HTML 解析失败。
///
/// 绅士无签名与解密；这些错误只在本来源边界内使用，
/// 越过公开 Services 前必须经过 `SourceErrorMapper` 转换为安全的公共错误。
/// 无业务码：公共错误映射直接使用 `SourcePublicErrorMapping` 的默认实现。
enum ShenshiAPIError: Error, SourceDiagnosableError, SourcePublicErrorMapping {
    /// 登录响应明确表示账号或密码不成立。
    case authenticationRejected

    /// 调用方传入非法参数（程序错误），例如页码或分类 ID 非法。
    case invalidArgument

    /// 请求缺少相对地址，或无法与当前 Host 组合成有效地址。
    case invalidRequest

    /// 响应为空、编码不符，或页面结构无法解析出预期内容。
    case invalidResponse

    var publicError: ComicSourceError {
        switch self {
        case .authenticationRejected:
            .authenticationRequired
        case .invalidArgument, .invalidRequest, .invalidResponse:
            .invalidResponse
        }
    }

    /// 日志用类别名。
    var diagnosticName: String {
        switch self {
        case .authenticationRejected:
            "authenticationRejected"
        case .invalidArgument:
            "invalidArgument"
        case .invalidRequest:
            "invalidRequest"
        case .invalidResponse:
            "invalidResponse"
        }
    }
}

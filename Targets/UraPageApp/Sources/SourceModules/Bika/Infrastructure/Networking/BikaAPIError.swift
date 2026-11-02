/// 描述哔咔请求构造、响应包装和业务状态校验失败。
///
/// 只在本来源边界内使用；越过公开 Services 前必须经过
/// `SourceErrorMapper` 转换为安全的公共错误。
enum BikaAPIError: Error, SourceDiagnosableError, SourcePublicErrorMapping {
    /// 调用方传入非法参数（程序错误），例如页码小于 1 或缺少标识。
    case invalidArgument

    /// 请求缺少 URL、HTTP Method，或相对地址无法与当前 Host 组合。
    case invalidRequest

    /// 服务端响应包装或当前接口 DTO 不符合预期格式。
    case invalidResponse

    /// HTTP 成功，但哔咔外层响应返回了非成功业务码。
    case serverRejected(code: Int)

    /// 日志用类别名；只保留安全数值码。
    var diagnosticName: String {
        switch self {
        case .invalidArgument:
            "invalidArgument"
        case .invalidRequest:
            "invalidRequest"
        case .invalidResponse:
            "invalidResponse"
        case let .serverRejected(code):
            "serverRejected(\(code))"
        }
    }

    /// 只保留安全的服务端业务码；其余 case 走协议默认映射收敛为 `invalidResponse`。
    var serverRejectionCode: Int? {
        switch self {
        case let .serverRejected(code):
            code
        default:
            nil
        }
    }
}

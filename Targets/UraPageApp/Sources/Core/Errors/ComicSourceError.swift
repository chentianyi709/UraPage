/// 描述所有漫画源在公共边界上允许暴露的有限错误。
///
/// 具体来源在各自边界先转换协议、签名、解密或解析错误，
/// 不能把 Alamofire、URLSession、HTML 文案、Cookie、私有 Host
/// 或响应正文带进公共错误。
enum ComicSourceError: Error, Equatable, Sendable {
    /// 请求携带的漫画、章节、图片等身份不属于当前来源，或缺少必要身份。
    case invalidIdentity

    /// 当前操作需要有效登录状态或来源凭证。
    case authenticationRequired

    /// 设备当前无法连接网络，或无法连接目标服务器。
    case networkUnavailable

    /// 请求在规定时间内没有完成。
    case timedOut

    /// 服务端限制了请求频率；`retryAfter` 是已知的建议等待时间。
    case rateLimited(retryAfter: Duration?)

    /// 响应缺失、格式错误，或无法完成来源内部的解析与解码。
    case invalidResponse

    /// 服务端明确拒绝了请求；`code` 只保留可安全暴露的状态码或业务码。
    case serverRejected(code: String?)
}

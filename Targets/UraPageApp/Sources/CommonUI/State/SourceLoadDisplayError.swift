/// 保存漫画源页面首次加载失败时可以共同展示的基础错误语义。
///
/// 只保留公共含义，不携带响应正文、业务码或来源内部细节。
enum SourceLoadDisplayError: Equatable, Sendable {
    /// 当前操作需要来源账号或有效凭证。
    case authenticationRequired

    /// 当前无法连接网络或目标服务器。
    case networkUnavailable

    /// 请求在规定时间内没有完成。
    case timedOut

    /// 服务端限制了当前请求频率。
    case rateLimited

    /// 当前错误没有更适合向用户展示的公共分类。
    case unavailable

    /// 将任意错误转换为不包含来源内部细节的展示错误。
    ///
    /// 只有 `ComicSourceError` 的公共分类可以映射；其余错误统一归为 `.unavailable`，
    /// 页面不需要在每处重复判断错误类型。
    init(_ error: any Error) {
        guard let sourceError = error as? ComicSourceError else {
            self = .unavailable
            return
        }

        switch sourceError {
        case .authenticationRequired:
            self = .authenticationRequired
        case .networkUnavailable:
            self = .networkUnavailable
        case .timedOut:
            self = .timedOut
        case .rateLimited:
            self = .rateLimited
        case .invalidIdentity, .invalidResponse, .serverRejected:
            self = .unavailable
        }
    }

    /// 返回所有漫画源页面都可以使用的简短处理提示。
    var message: String {
        switch self {
        case .authenticationRequired:
            "请先登录当前漫画源"
        case .networkUnavailable:
            "网络连接失败，请检查网络后重试"
        case .timedOut:
            "请求超时，请稍后重试"
        case .rateLimited:
            "请求过于频繁，请稍后再试"
        case .unavailable:
            "暂时无法完成请求，请稍后重试"
        }
    }
}

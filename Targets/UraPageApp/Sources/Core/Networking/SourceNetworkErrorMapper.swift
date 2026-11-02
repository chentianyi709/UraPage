import Alamofire
import Foundation

/// 将各漫画源共同遇到的底层网络错误转换为公共错误。
///
/// 只在这里处理 URLSession 与 Alamofire 的通用语义；
/// 来源自己的协议、签名、解密与解析错误必须在来源边界先转换。
/// 不向调用方暴露第三方库类型或响应正文。
enum SourceNetworkErrorMapper {
    /// 判断错误是否已被公共映射识别为认证失效（HTTP 401 → `.authenticationRequired`）。
    ///
    /// 来源 Client 用它做认证失效收口：只有服务端明确拒绝认证才清凭证，普通失败不当作失效。
    static func isAuthenticationRejection(_ error: any Error) -> Bool {
        guard let sourceError = map(error) as? ComicSourceError else {
            return false
        }

        if case .authenticationRequired = sourceError {
            return true
        }

        return false
    }

    /// 判断当前 Host 的连接、DNS 或 TLS 失败，供来源选择已约定的恢复动作。
    /// 超时、普通断网和 HTTP 错误不在此列；判定本身不触发换线。
    static func isHostConnectionFailure(_ error: any Error) -> Bool {
        guard let urlError = underlyingURLError(in: error) else {
            return false
        }

        switch urlError.code {
        case .cannotFindHost,
             .cannotConnectToHost,
             .dnsLookupFailed,
             .secureConnectionFailed,
             .serverCertificateHasBadDate,
             .serverCertificateUntrusted,
             .serverCertificateHasUnknownRoot,
             .serverCertificateNotYetValid,
             .clientCertificateRejected,
             .clientCertificateRequired:
            return true
        default:
            return false
        }
    }

    /// 判断错误是否表示取消（Swift Concurrency、URLSession 或 Alamofire）。
    ///
    /// 取消是正常控制流，不能当成网络失败展示或记录。
    static func isCancellation(_ error: any Error) -> Bool {
        if error is CancellationError {
            return true
        }

        if let urlError = error as? URLError, urlError.code == .cancelled {
            return true
        }

        if let alamofireError = error as? AFError,
           case .explicitlyCancelled = alamofireError {
            return true
        }

        if let underlyingError = (error as? AFError)?.underlyingError {
            return isCancellation(underlyingError)
        }
        return false
    }

    /// 保留取消语义，并隐藏 Alamofire、URLSession 和响应正文等底层细节。
    ///
    /// 已经转换过的公共错误保持原样，避免在多层边界重复映射。
    static func map(_ error: any Error) -> any Error {
        if isCancellation(error) {
            return CancellationError()
        }

        if let publicError = error as? ComicSourceError {
            return publicError
        }

        if let alamofireError = error as? AFError {
            if let statusError = statusError(from: alamofireError) {
                return statusError
            }
            if let urlError = underlyingURLError(in: alamofireError) {
                return publicError(from: urlError)
            }
            return ComicSourceError.invalidResponse
        }

        if let urlError = error as? URLError {
            return publicError(from: urlError)
        }

        // 未知错误不向 App 暴露具体库类型或内部响应结构。
        return ComicSourceError.invalidResponse
    }

    /// 将 HTTP 状态码转换为不携带响应正文的公共错误。
    private static func statusError(from error: AFError) -> ComicSourceError? {
        guard case let .responseValidationFailed(reason) = error,
              case let .unacceptableStatusCode(code) = reason else {
            return nil
        }

        switch code {
        case 401:
            return .authenticationRequired
        case 429:
            // 公共映射不解析各来源可能采用的 Retry-After 格式。
            return .rateLimited(retryAfter: nil)
        default:
            return .serverRejected(code: String(code))
        }
    }

    /// 区分超时、网络不可用和其它 URLSession 错误。
    private static func publicError(from error: URLError) -> ComicSourceError {
        switch error.code {
        case .timedOut:
            return .timedOut
        case .cannotFindHost,
             .cannotConnectToHost,
             .networkConnectionLost,
             .dnsLookupFailed,
             .notConnectedToInternet,
             .internationalRoamingOff,
             .callIsActive,
             .dataNotAllowed:
            return .networkUnavailable
        default:
            return .invalidResponse
        }
    }

    /// 从直接错误或 Alamofire 的嵌套错误中查找 URLSession 原始错误。
    ///
    /// 也供业务操作的脱敏诊断复用，避免同一份递归查找写两遍。
    static func underlyingURLError(in error: any Error) -> URLError? {
        if let urlError = error as? URLError {
            return urlError
        }

        if let alamofireError = error as? AFError,
           let underlyingError = alamofireError.underlyingError {
            return underlyingURLError(in: underlyingError)
        }
        return nil
    }
}

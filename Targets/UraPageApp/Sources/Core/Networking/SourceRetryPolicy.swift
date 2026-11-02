import Alamofire
import Foundation

/// 提供来源业务 Session 共用的安全读取重试策略。
///
/// 只允许 GET/HEAD；每个 Alamofire Request 首次失败后最多额外重试两次（共三次传输尝试），
/// 退避 `0.5s`、`1.0s`。写操作（POST/PUT/DELETE）即使遇到同类错误也不重试。
/// Client 重放 operation 时会创建新的 Request，次数与本策略分别计算。
/// 各来源在自己的拦截器内安装该策略，不共享跨来源 Interceptor。
enum SourceRetryPolicy {
    /// 创建一个新的安全读取重试策略。
    ///
    /// 每次重试都由 Alamofire 从原始 request 重新执行适配，来源可据此重新生成
    /// 时间戳与签名，不复用旧签名。
    static func make() -> RetryPolicy {
        RetryPolicy(
            retryLimit: 2,
            exponentialBackoffBase: 2,
            exponentialBackoffScale: 0.5,
            retryableHTTPMethods: [.get, .head],
            retryableHTTPStatusCodes: Set(500 ... 599).union([429]),
            retryableURLErrorCodes: [
                .timedOut,
                .networkConnectionLost,
                .cannotConnectToHost,
                .cannotFindHost,
                .dnsLookupFailed,
                .secureConnectionFailed,
            ],
        )
    }
}

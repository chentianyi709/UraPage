import Alamofire

/// 需要统一安全重试策略的请求拦截器。
///
/// 三个来源的重试语义完全一致（只重试安全读取、写操作不重试、按公共退避策略），
/// 差异只在 `adapt` 里如何重新生成鉴权与签名，因此这里提供唯一的 `retry` 实现，
/// 来源拦截器只声明遵循本协议即可。Alamofire 会在每次重试前重新调用 `adapt`，
/// 所以重试不会复用旧的时间戳或签名。需要不同策略的来源可实现自己的 `retry` 覆盖它。
protocol SourceRetryingRequestInterceptor: RequestInterceptor {}

extension SourceRetryingRequestInterceptor {
    /// 对短暂服务端或连接故障执行退避重试。
    func retry(
        _ request: Request,
        for session: Session,
        dueTo error: any Error,
        completion: @escaping @Sendable (RetryResult) -> Void,
    ) {
        SourceRetryPolicy.make().retry(request, for: session, dueTo: error) { result in
            #if DEBUG
                switch result {
                case .retry, .retryWithDelay:
                    // 只在真的重试时记录：用于解释延迟与重复请求。
                    AppLogger.debug(
                        "安全读取按策略重试，source=\(Self.self)，request=\(request.id)，session=\(ObjectIdentifier(session).hashValue)，retry=\(request.retryCount + 1)，\(SourceErrorDiagnostics.summary(for: error))",
                        category: "Source.Network",
                    )

                default:
                    if request.retryCount > 0 {
                        AppLogger.debug(
                            "停止网络重试，source=\(Self.self)，request=\(request.id)，session=\(ObjectIdentifier(session).hashValue)，retries=\(request.retryCount)，cancelled=\(SourceNetworkErrorMapper.isCancellation(error))，\(SourceErrorDiagnostics.summary(for: error))",
                            category: "Source.Network",
                        )
                    }
                }
            #endif

            completion(result)
        }
    }
}

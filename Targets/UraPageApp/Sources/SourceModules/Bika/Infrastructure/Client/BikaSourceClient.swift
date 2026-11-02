import Alamofire
import Foundation

/// 保存哔咔业务请求共同使用的 Base URL 和 Session。
struct BikaPreparedState: SourceSessionPreparedState {
    /// 创建 Session 时绑定的 API 地址。
    let baseURL: URL

    /// 已经安装哔咔签名拦截器的业务 Session。
    let session: Session
}

/// 持有哔咔当前业务 Session，并为认证与浏览接口提供稳定请求环境。
///
/// 准备状态机由公共 `SourceClientState` 承担；本类型在基座原语上组合哔咔特有的
/// 线路恢复读取，并为账号层提供稳定 Client。
actor BikaSourceClient: SourceAuthenticatedClient {
    let hostProvider: SourceHostProvider

    /// 与图片服务共享并持久化哔咔来源的全局行为偏好。
    let sourcePreferences = BikaSourcePreferences()

    let clientState: SourceClientState<BikaPreparedState>

    /// 串行执行 Host 变更，并让读取等待在途变更结束。
    let hostOperations = SourceHostOperationRunner()

    /// 合并同一连接故障触发的 Session 重建。
    private var hostRecoveryTask: Task<BikaPreparedState, any Error>?

    #if DEBUG
        /// 仅在单次读取的任务作用域内关联诊断；不进入 Release，也不参与业务状态提交。
        @TaskLocal private static var diagnosticReadID = ""
    #endif

    /// 认证失效收口（公共入口）：判定 401 并通知账号 owner 清凭证、发布未登录。
    let authentication: SourceAuthenticationHandler

    @MainActor
    init(
        hostProvider: SourceHostProvider,
        access: BikaAccountAccessStore,
    ) {
        self.hostProvider = hostProvider
        authentication = SourceAuthenticationHandler(access: access)

        // 捕获已初始化的依赖值：既不引用尚未完成初始化的 self，也让准备闭包与属性共享同一实例。
        clientState = SourceClientState { [sourcePreferences] in
            try await BikaSourceClient.makePreparedState(
                hostProvider: hostProvider,
                access: access,
                sourcePreferences: sourcePreferences,
            )
        }
    }

    /// 返回准备完成的业务状态，并合并并发的首次准备请求。
    func preparedState() async throws -> BikaPreparedState {
        try await hostOperations.waitForInFlight()
        // 有线路恢复在途时，所有调用方共享它，避免并发重建多个 Session。
        if let hostRecoveryTask {
            return try await SourceSharedWait.value(of: hostRecoveryTask)
        }
        return try await clientState.preparedState()
    }

    /// 配置变化的重放由公共状态机处理；连接类失败额外重建同 Host Session 读取一次。
    /// 首次与恢复请求的最终错误都交给公共 read 处理认证，不递归增加重放。
    func performRead<Value: Sendable>(
        _ operation: @Sendable (BikaPreparedState) async throws -> Value,
    ) async throws -> Value {
        #if DEBUG
            return try await Self.$diagnosticReadID.withValue(UUID().uuidString) {
                try await readRecoveringConnection(operation)
            }
        #else
            return try await readRecoveringConnection(operation)
        #endif
    }

    /// 两种构建共用恢复流程；Debug 的任务作用域只负责提供日志关联标识。
    private func readRecoveringConnection<Value: Sendable>(
        _ operation: @Sendable (BikaPreparedState) async throws -> Value,
    ) async throws -> Value {
        #if DEBUG
            let readID = Self.diagnosticReadID
        #endif
        let generationAtStart = await clientState.configurationGeneration

        do {
            return try await clientState.read(operation)
        } catch {
            // 只有连接类失败才重建同一 Host 的 Session 再试一次（不换线路）。
            guard SourceNetworkErrorMapper.isHostConnectionFailure(error) else {
                throw error
            }

            #if DEBUG
                let recoveryStartedAt = ContinuousClock.now
                AppLogger.debug(
                    "连接恢复开始，read=\(readID)，startGeneration=\(generationAtStart)，\(SourceErrorDiagnostics.summary(for: error))",
                    category: "Bika.Recovery",
                )
            #endif
            do {
                let recoveredState = try await recoverPreparedState(failedGeneration: generationAtStart)
                try Task.checkCancellation()
                let value = try await operation(recoveredState)
                #if DEBUG
                    AppLogger.debug(
                        "连接恢复结束，read=\(readID)，result=success，耗时=\(AppLogger.milliseconds(recoveryStartedAt.duration(to: .now)))",
                        category: "Bika.Recovery",
                    )
                #endif
                return value
            } catch {
                #if DEBUG
                    AppLogger.debug(
                        "连接恢复结束，read=\(readID)，result=\(SourceNetworkErrorMapper.isCancellation(error) ? "cancelled" : "failed")，耗时=\(AppLogger.milliseconds(recoveryStartedAt.duration(to: .now)))，\(SourceErrorDiagnostics.summary(for: error))",
                        category: "Bika.Recovery",
                    )
                #endif
                throw error
            }
        }
    }

    /// 合并并发 Host 恢复：使旧状态失效后按同一 Host 重建 Session。
    private func recoverPreparedState(failedGeneration: Int) async throws -> BikaPreparedState {
        let currentGeneration = await clientState.configurationGeneration
        // 期间代次已变：说明已有人完成切换/恢复，直接用当前状态即可。
        if failedGeneration != currentGeneration {
            return try await clientState.preparedState()
        }
        // 已经有人开始恢复：共享同一份重建任务。
        if let hostRecoveryTask {
            return try await SourceSharedWait.value(of: hostRecoveryTask)
        }

        // 重建 = 先使旧 Session 失效，再按同一 Host 重新准备（不是换线路）。
        let task = Task { [clientState] in
            await clientState.invalidate()
            return try await clientState.preparedState()
        }
        hostRecoveryTask = task

        do {
            let recoveredState = try await SourceSharedWait.value(of: task)
            hostRecoveryTask = nil
            return recoveredState
        } catch {
            hostRecoveryTask = nil
            throw error
        }
    }

    /// 准备当前 Host，再创建绑定该地址和固定协议头的签名 Session。
    private static func makePreparedState(
        hostProvider: SourceHostProvider,
        access: BikaAccountAccessStore,
        sourcePreferences: BikaSourcePreferences,
    ) async throws -> BikaPreparedState {
        let baseURL = try await hostProvider.baseURL()
        let credential = try await credentialSnapshot(from: access)
        let requestInterceptor = BikaRequestInterceptor(
            baseURL: baseURL,
            credential: credential,
            sourcePreferences: sourcePreferences,
        )
        return BikaPreparedState(
            baseURL: baseURL,
            session: makeSession(requestInterceptor: requestInterceptor),
        )
    }

    /// 只把与同一凭证代次对应的凭证绑定到 Session，避免账号切换时误标请求代次。
    ///
    /// 读取期间账号若被替换，代次会变化；账号操作只会让代次前进，因此重读必然收敛。
    private static func credentialSnapshot(
        from access: BikaAccountAccessStore,
    ) async throws -> BikaCredential? {
        while true {
            try Task.checkCancellation()
            let generation = await access.credentialGeneration
            let credential = try await access.credentialForSession()
            guard await access.credentialGeneration == generation else { continue }

            return credential
        }
    }

    /// 创建无 Cookie、无 URLCache，并统一安装哔咔签名拦截器的 Session。
    static func makeSession(requestInterceptor: BikaRequestInterceptor) -> Session {
        let configuration = URLSessionConfiguration.af.ephemeral
        SourceConfiguration.Session.applyCookieFreeDefaults(to: configuration)

        return Session(configuration: configuration, interceptor: requestInterceptor)
    }

    static func makeSession(
        baseURL: URL,
        credential: BikaCredential?,
        sourcePreferences: BikaSourcePreferences,
    ) -> Session {
        makeSession(
            requestInterceptor: BikaRequestInterceptor(
                baseURL: baseURL,
                credential: credential,
                sourcePreferences: sourcePreferences,
            ),
        )
    }
}

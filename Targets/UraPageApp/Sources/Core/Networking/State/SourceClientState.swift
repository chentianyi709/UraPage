import Foundation

/// 来源 Client 的准备状态必须能取消该状态绑定的在途请求。
///
/// 在 Host/账号切换或状态失效时由 `SourceClientState.invalidate()` 调用。
protocol SourceClientPreparedState: Sendable {
    /// 取消该准备状态绑定的全部在途网络请求。
    func cancelInFlightRequests()
}

/// 来源 Client 共用的最小准备状态机。
///
/// 只负责：首次准备去重、配置 generation、旧状态失效、取消感知等待、可选的一次重试读取。
/// 不包含 Host 恢复、鉴权或来源 Setting 语义；Host 操作的串行化与"读取前等待在途 Host 操作"
/// 由各来源 Client 在本类型提供的原语上组合。
actor SourceClientState<PreparedState: SourceClientPreparedState> {
    typealias Prepare = @Sendable () async throws -> PreparedState

    private let prepare: Prepare
    private var state: PreparedState?
    private var preparationTask: Task<PreparedState, any Error>?
    private var generation = 0

    init(prepare: @escaping Prepare) {
        self.prepare = prepare
    }

    /// 当前配置代次；每次失效递增，用于拒绝旧结果。
    var configurationGeneration: Int {
        generation
    }

    /// 返回准备完成的业务状态，合并并发首次准备。
    ///
    /// 调用方取消只退出自己的等待，共享准备任务继续；其它等待者仍取得同一结果。
    func preparedState() async throws -> PreparedState {
        // 入口先尊重取消：调用方已取消时立即结束，不读取也不创建准备状态。
        try Task.checkCancellation()

        // 已有可用状态，直接返回，不再触碰网络或准备任务。
        if let state {
            return state
        }

        let operationGeneration = generation
        let task: Task<PreparedState, any Error>
        if let preparationTask {
            task = preparationTask
        } else {
            // 共享工作自己提交并清理，等待者只取结果：旧等待者不会清掉后来创建的任务。
            // 即使全部页面都已取消等待，完成的准备状态仍可供下次访问复用。
            AppLogger.debug("开始准备业务状态（首次或重建）", category: "Source.Client")
            task = Task {
                defer {
                    if operationGeneration == generation {
                        preparationTask = nil
                    }
                }
                let prepared = try await prepare()
                guard operationGeneration == generation else {
                    prepared.cancelInFlightRequests()
                    throw CancellationError()
                }

                state = prepared
                return prepared
            }
            preparationTask = task
        }

        let prepared = try await SourceSharedWait.value(of: task)
        // 工作完成到等待者恢复之间仍可能切换配置，读取端继续复用同一代次校验。
        guard operationGeneration == generation else {
            throw CancellationError()
        }

        try Task.checkCancellation()
        return prepared
    }

    /// 用新状态替换当前已准备状态（例如图源切换成功后更新 Setting）。
    func replace(_ newState: PreparedState) {
        state = newState
    }

    /// 使旧状态失效：递增 generation、取消准备任务、取消旧请求。
    func invalidate() {
        // 先递增代次，让已经在途、尚未提交的准备结果立即作废。
        generation += 1
        preparationTask?.cancel()
        preparationTask = nil
        // 取消旧 Session 上所有在途请求，避免切换后仍写入旧环境的结果。
        state?.cancelInFlightRequests()
        state = nil
        AppLogger.debug("业务状态失效并取消在途请求，generation=\(generation)", category: "Source.Client")
    }

    /// 安全读取：配置代次变化时用新状态重试一次；不包含来源特有恢复。
    func read<Value: Sendable>(
        _ operation: @Sendable (PreparedState) async throws -> Value,
    ) async throws -> Value {
        // 记录发起读取时的代次；请求失败后据此判断是否值得重试。
        var failedGeneration = generation

        do {
            let prepared = try await preparedState()
            failedGeneration = generation
            return try await operation(prepared)
        } catch {
            // 代次没变：是真实业务/网络失败，原样交给调用方。
            guard failedGeneration != generation else {
                throw error
            }

            // 代次变了：本次失败很可能源于一次成功的 Host/账号切换，用新状态重试一次。
            try Task.checkCancellation()
            #if DEBUG
                AppLogger.debug(
                    "配置变化后准备重放读取，state=\(PreparedState.self)，failedGeneration=\(failedGeneration)，currentGeneration=\(generation)，\(SourceErrorDiagnostics.summary(for: error))",
                    category: "Source.Client",
                )
            #endif
            let prepared = try await preparedState()
            try Task.checkCancellation()
            return try await operation(prepared)
        }
    }
}

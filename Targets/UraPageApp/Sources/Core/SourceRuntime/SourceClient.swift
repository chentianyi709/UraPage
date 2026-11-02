import Foundation

/// 来源 Client 的公共执行契约；具体 actor 只提供状态 owner 与自己的请求、准备规则。
///
/// Host 变更与安全读取的顺序由默认实现负责；账号能力由 SourceAuthenticatedClient 补充。来源有额外恢复规则时实现
/// `performRead` / `preparedState`，保留公共 `read`；队列内部直接使用 `clientState`，不能等待自己所在的队列。
protocol SourceClient: Actor {
    associatedtype PreparedState: SourceClientPreparedState

    var clientState: SourceClientState<PreparedState> { get }
    var hostProvider: SourceHostProvider { get }
    var hostOperations: SourceHostOperationRunner { get }

    func preparedState() async throws -> PreparedState
    func read<Value: Sendable>(
        _ operation: @Sendable (PreparedState) async throws -> Value,
    ) async throws -> Value

    /// 返回本源 Host 切换成功事件流；订阅方负责在生命周期结束时取消。
    func hostChangeStream() async -> AsyncStream<SourceHostChange>

    /// 读取执行点：默认复用状态机；来源仅在这里补充有界恢复，最终错误交给 read 统一处理。
    /// 不重复等待 Host 操作或处理认证，也不递归调用 read 增加重放次数。
    func performRead<Value: Sendable>(
        _ operation: @Sendable (PreparedState) async throws -> Value,
    ) async throws -> Value
}

extension SourceClient {
    /// 普通读取先等在途配置变更；共享准备任务不受单个页面取消影响。
    func preparedState() async throws -> PreparedState {
        try await hostOperations.waitForInFlight()
        return try await clientState.preparedState()
    }

    /// 匿名来源的安全读取同样复用配置变化后的一次恢复，不要求伪造账号 owner。
    func read<Value: Sendable>(
        _ operation: @Sendable (PreparedState) async throws -> Value,
    ) async throws -> Value {
        try await hostOperations.waitForInFlight()
        return try await performRead(operation)
    }

    /// 配置变化后的单次重放由状态机负责；普通网络失败仍直接抛出。
    func performRead<Value: Sendable>(
        _ operation: @Sendable (PreparedState) async throws -> Value,
    ) async throws -> Value {
        try await clientState.read(operation)
    }

    /// Host 切换事件由串行变更 runner 发布，默认实现直接转发本源流。
    func hostChangeStream() async -> AsyncStream<SourceHostChange> {
        await hostOperations.makeHostChangeStream()
    }

    func hostSelectionSnapshot() async throws -> SourceHostSelectionSnapshot {
        try await hostProvider.selectionSnapshot()
    }

    /// 地址确实变化且成功后才失效 Session；重复选择当前地址与失败都保留原有可用状态。
    func selectHost(baseURL: URL) async throws -> SourceHostSelectionSnapshot {
        try await hostOperations.applyHostChange(to: clientState) {
            try await self.hostProvider.select(baseURL: baseURL)
        }
    }
}

/// 具有账号的来源在基础 Client 上声明认证能力；匿名来源只遵循 SourceClient。
protocol SourceAuthenticatedClient: SourceClient {
    var authentication: SourceAuthenticationHandler { get }
}

extension SourceAuthenticatedClient {
    /// 首次读取与来源恢复的最终错误统一经过认证清理；旧凭证的迟到错误不能清除新账号。
    func read<Value: Sendable>(
        _ operation: @Sendable (PreparedState) async throws -> Value,
    ) async throws -> Value {
        try await hostOperations.waitForInFlight()
        let credentialGeneration = await authentication.credentialGeneration()

        do {
            return try await performRead(operation)
        } catch {
            if await authentication.handle(error, credentialGeneration: credentialGeneration) {
                await clientState.invalidate()
            }
            throw error
        }
    }

    /// 执行一次非幂等写操作：只提交一次，不进入读取的配置变化／连接失败重放。
    ///
    /// 先走来源自己的准备流程（例如哔咔的同 Host 连接恢复等待），再读取提交时的配置与凭证代次。
    /// 请求成功后直接返回已生效的结果；配置变化只在提交失败时按取消收口，避免丢弃服务端已经执行的切换。
    /// 认证失效仍按提交时的凭证代次处理，避免旧请求清掉新账号。
    func write<Value: Sendable>(
        _ operation: @Sendable (PreparedState) async throws -> Value,
    ) async throws -> Value {
        try await hostOperations.waitForInFlight()
        let preparedState = try await preparedState()
        let credentialGeneration = await authentication.credentialGeneration()
        let configurationGeneration = await clientState.configurationGeneration
        try Task.checkCancellation()

        do {
            return try await operation(preparedState)
        } catch {
            guard await clientState.configurationGeneration == configurationGeneration else {
                throw CancellationError()
            }

            if await authentication.handle(error, credentialGeneration: credentialGeneration) {
                await clientState.invalidate()
            }
            throw error
        }
    }

    /// 登录失败只表示本次凭证被拒，不能清除当前账号的认证事实。
    /// 保留原有配置变化重放；直接读取状态机，不进入来源的额外连接恢复。
    func readIgnoringAuthenticationRejection<Value: Sendable>(
        _ operation: @Sendable (PreparedState) async throws -> Value,
    ) async throws -> Value {
        try await hostOperations.waitForInFlight()
        return try await clientState.read(operation)
    }

    /// 账号 owner 在凭证变更后调用；下次请求按新凭证重新准备。
    func credentialDidChange() async {
        await clientState.invalidate()
    }
}

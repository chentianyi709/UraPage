import Foundation

/// 串行执行一个来源的 Host 环境变更（Host 切换、图源切换），并让读取等待在途变更结束。
///
/// 每个来源 Client 持有唯一实例；语义与《漫画源接入约定》的设置互斥规则一致：
/// - 变更依次排队，并发提交不会互相覆盖，也不会读到变更中途的状态；
/// - 重复选择当前地址不算变更：不使准备状态失效，也不发布事件；
/// - 已接受的变更不因调用方（设置页面）取消而中止；
/// - 等待方取消只退出自己的等待，共享的变更继续执行；
/// - 队列 operation 内不得再调用本 runner（`enqueue`／`applyHostChange`／`waitForInFlight`），
///   也不得调用会等待在途变更的 `SourceClient.read`／`preparedState`：它们都会等待包含自身的
///   队列尾而死锁。队列内需要读取准备状态时，直接使用 `clientState`。
actor SourceHostOperationRunner {
    /// 串行链尾，始终代表“最后一个已接受的变更完成”。
    private var tail: Task<Void, Never> = Task {}

    /// Host 切换成功事件的订阅者；每条事件只在变更完成后产生一次。
    private var changeContinuations: [UUID: AsyncStream<SourceHostChange>.Continuation] = [:]

    init() {}

    /// 排队执行一次 Host 变更；只有地址确实变化且成功后，才使旧准备状态失效并发布事件。
    ///
    /// 调用方取消只退出自己的等待，不中止已接受的变更。
    /// 旧状态失效与事件发布都在队列内完成：设置页关闭后变更仍继续，订阅方不会漏掉已生效的切换。
    func applyHostChange(
        to state: SourceClientState<some SourceClientPreparedState>,
        _ operation: @escaping @Sendable () async throws -> (
            snapshot: SourceHostSelectionSnapshot,
            didChange: Bool,
        ),
    ) async throws -> SourceHostSelectionSnapshot {
        try await enqueue {
            let result = try await operation()
            guard result.didChange else { return result.snapshot }

            await state.invalidate()
            await self.publishHostChange()
            return result.snapshot
        }
    }

    /// 新建一条 Host 切换事件流；订阅方负责在生命周期结束时取消。
    func makeHostChangeStream() -> AsyncStream<SourceHostChange> {
        let id = UUID()
        let (stream, continuation) = AsyncStream.makeStream(
            of: SourceHostChange.self,
            bufferingPolicy: .bufferingNewest(1),
        )
        changeContinuations[id] = continuation
        // 弱引用自身：continuation 由本 actor 持有，强引用会形成 actor → continuation → actor 的环。
        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeChangeContinuation(id) }
        }
        return stream
    }

    private func removeChangeContinuation(_ id: UUID) {
        changeContinuations[id] = nil
    }

    /// 通知所有订阅者一次已生效的 Host 切换；旧事件由 `bufferingNewest(1)` 合并。
    private func publishHostChange() {
        for continuation in changeContinuations.values {
            continuation.yield(SourceHostChange())
        }
    }

    /// 排队执行一次不改变准备状态的变更（例如只更新远程 Setting 的图源切换）。
    func enqueue<Value: Sendable>(
        _ operation: @escaping @Sendable () async throws -> Value,
    ) async throws -> Value {
        let previous = tail

        // 变更本身不感知调用方取消：先等前一个变更结束，再执行。
        // 任务体不访问本 actor 状态，用 `@concurrent` 起步，避免占用变更队列的执行器。
        let task = Task { @concurrent in
            await previous.value
            return try await operation()
        }
        // 链只表示"上一个变更已结束"：变更自身的错误由各自调用方处理，因此这里吞掉错误。
        tail = Task { _ = try? await task.value }

        // 调用方取消时立即退出自己的等待，共享的变更继续执行。
        return try await SourceSharedWait.value(of: task)
    }

    /// 等待所有在途变更结束；变更自身的错误由各自调用方处理，调用方取消时立即退出等待。
    func waitForInFlight() async throws {
        try await SourceSharedWait.value(of: tail)
    }
}

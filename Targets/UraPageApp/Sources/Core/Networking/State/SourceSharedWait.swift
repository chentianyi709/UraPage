import Synchronization

/// 等待一个共享任务，同时允许调用方取消只退出自己的等待。
///
/// 语义：
/// - 调用方取消：立即抛出 `CancellationError`，不等待共享任务；
/// - 共享任务继续运行，其它等待者仍取得同一结果；
/// - 结果或错误只恢复一次。
///
/// 用于 Host 解析、Client 首次准备等“一次共享工作、多个等待者”的场景。
enum SourceSharedWait {
    /// 等待一个不可失败的共享任务；调用方取消时立即抛出 `CancellationError`。
    static func value<Success: Sendable>(
        of task: Task<Success, Never>,
    ) async throws -> Success {
        try await value(of: Task<Success, any Error> { await task.value })
    }

    /// 等待共享任务的结果；调用方取消不取消共享任务。
    static func value<Success: Sendable>(
        of task: Task<Success, any Error>,
    ) async throws -> Success {
        // 每个等待者各自持有一个一次性 continuation 持有者，彼此互不影响。
        let waiter = SourceSharedWaitWaiter<Success>()

        // observer 只把共享任务的结果转交给 waiter。它挂在共享任务上，
        // 不会因为某个调用方取消而停止，因此其它等待者仍能拿到结果。
        _ = Task {
            do {
                try await waiter.complete(with: .success(task.value))
            } catch {
                waiter.complete(with: .failure(error))
            }
        }

        // 先挂上取消处理再进入等待：若调用方此刻取消，onCancel 立即用
        // CancellationError 完成 waiter，从而退出自己的等待。
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                waiter.register(continuation)
            }
        } onCancel: {
            waiter.complete(with: .failure(CancellationError()))
        }
    }
}

/// 一次性 continuation 持有者：在“调用方取消”和“共享任务完成”之间保证只恢复一次。
private final class SourceSharedWaitWaiter<Success: Sendable>: Sendable {
    /// 三种状态保证 continuation 只恢复一次：
    /// `waiting` 还没注册，`suspended` 已注册等待中，`completed` 结果已到。
    private enum State {
        case waiting
        case suspended(CheckedContinuation<Success, any Error>)
        case completed(Result<Success, any Error>)
    }

    private let state = Mutex<State>(.waiting)

    /// 注册 continuation；若结果已先到（例如已取消），立即恢复。
    func register(_ continuation: CheckedContinuation<Success, any Error>) {
        let existing: Result<Success, any Error>? = state.withLock { state in
            switch state {
            case .waiting:
                state = .suspended(continuation)
                return nil

            case let .completed(result):
                return result

            case .suspended:
                return nil
            }
        }

        if let existing {
            continuation.resume(with: existing)
        }
    }

    /// 完成等待；只恢复一次，后续调用被忽略。
    func complete(with result: Result<Success, any Error>) {
        let continuation: CheckedContinuation<Success, any Error>? = state.withLock { state in
            switch state {
            case .waiting:
                state = .completed(result)
                return nil

            case let .suspended(continuation):
                state = .completed(result)
                return continuation

            case .completed:
                return nil
            }
        }

        continuation?.resume(with: result)
    }
}

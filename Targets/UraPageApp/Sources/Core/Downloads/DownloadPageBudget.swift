import Foundation

/// 全部作品共享的在途页任务名额。
///
/// 两个可调的并发上限（每来源作品数、单作品页数）相乘会放大在途页任务数，
/// 这个固定名额把它们压在同一水位：名额用完时新页排队等待，等待中被取消立即退出。
/// 只约束作品下载的页任务；Reader 的预加载走自己的窗口，不经过这里。
/// 名额上限必须 ≥ 1（由 `AppConfiguration.Downloads.maximumInFlightPageTasks` 提供）。
actor DownloadPageBudget {
    private struct Waiter {
        let id: UUID
        let continuation: CheckedContinuation<Bool, Never>
    }

    private let limit: Int
    private var activeCount = 0
    private var waiters: [Waiter] = []

    init(limit: Int) {
        // 0 会让所有页任务永久排队，属装配错误：直接暴露，不静默卡住下载。
        precondition(limit > 0, "页任务名额上限必须大于 0")
        self.limit = limit
    }

    /// 取得一个名额；名额已满时排队等待，返回 `false` 表示等待期间被取消。
    func acquire() async -> Bool {
        guard !Task.isCancelled else { return false }

        if activeCount < limit {
            activeCount += 1
            return true
        }

        let id = UUID()
        let granted = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                // 注册与取消之间存在竞态：已取消就不再入队，避免无人唤醒。
                guard !Task.isCancelled else {
                    continuation.resume(returning: false)
                    return
                }

                waiters.append(Waiter(id: id, continuation: continuation))
            }
        } onCancel: {
            Task { await self.cancelWaiter(id) }
        }

        // 名额可能在取消处理器之前就已转交；已取消就不要带着名额继续执行，立即归还给下一位。
        guard granted, !Task.isCancelled else {
            if granted {
                release()
            }
            return false
        }

        return true
    }

    /// 归还名额；有等待者时直接转交，不改变在途数。
    func release() {
        guard !waiters.isEmpty else {
            // 每个名额只对应一次成功 acquire；重复释放是调用错误，不能静默缩小在途数。
            precondition(activeCount > 0, "页任务名额重复释放")
            activeCount -= 1
            return
        }

        waiters.removeFirst().continuation.resume(returning: true)
    }

    /// 取消仍在排队的等待者；已被移交的名额不受影响。
    private func cancelWaiter(_ id: UUID) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else { return }

        waiters.remove(at: index).continuation.resume(returning: false)
    }
}

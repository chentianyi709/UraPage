import Foundation

/// 保留已脱离当前展示的任务；是否取消与是否等待回收是两个独立决定。
@MainActor
final class ReaderTaskRetirement {
    private var barrier: Task<Void, Never>?
    private var pendingGroups: [UUID: [Task<Void, Never>]] = [:]

    func cancel(
        _ tasks: [Task<Void, Never>],
        afterCompletion: (@Sendable () async -> Void)? = nil,
    ) {
        tasks.forEach { $0.cancel() }
        retain(tasks, afterCompletion: afterCompletion)
    }

    /// 切章后旧请求继续完成，不让关闭屏障阻塞新请求的创建。
    func retain(
        _ tasks: [Task<Void, Never>],
        afterCompletion: (@Sendable () async -> Void)? = nil,
    ) {
        guard !tasks.isEmpty || afterCompletion != nil else { return }

        let groupID = UUID()
        pendingGroups[groupID] = tasks
        let previous = barrier
        barrier = Task { @concurrent [weak self] in
            await previous?.value
            for task in tasks {
                await task.value
            }
            await afterCompletion?()
            await self?.finishGroup(groupID)
        }
    }

    private func finishGroup(_ id: UUID) {
        pendingGroups[id] = nil
    }

    /// 退出 Reader 才取消仍在执行的旧任务，并把等待屏障交给 session。
    func drain() -> [Task<Void, Never>] {
        pendingGroups.values.joined().forEach { $0.cancel() }
        pendingGroups.removeAll()
        defer { barrier = nil }
        return barrier.map { [$0] } ?? []
    }
}

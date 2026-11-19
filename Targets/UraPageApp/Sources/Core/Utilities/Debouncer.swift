import Foundation

/// 合并短时间内的多次触发：每次调用重置计时，只有最后一次会在延迟后执行。
///
/// 适用于「写入 → 刷新」这类高频信号——连续翻页、批量删除只需在停下后刷新一次。
/// 与 `Task.sleep` 的重试退避、延时卸载不同，这里的重点是**取消前一次**。
@MainActor
final class Debouncer {
    private var task: Task<Void, Never>?

    /// 重新计时并取消上一次待执行的动作。
    func schedule(
        after delay: Duration = .milliseconds(300),
        action: @escaping @MainActor () -> Void,
    ) {
        task?.cancel()
        task = Task {
            do {
                try await Task.sleep(for: delay)
            } catch {
                // 被下一次调用取消：不执行旧动作。
                return
            }

            action()
        }
    }

    /// 丢弃待执行的动作。
    func cancel() {
        task?.cancel()
        task = nil
    }

    deinit {
        task?.cancel()
    }
}

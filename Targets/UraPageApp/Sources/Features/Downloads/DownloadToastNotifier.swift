import Observation

/// 订阅下载进度流，在作品首次变为「已完成」时弹出成功 Toast。
///
/// 与「下载记录」页面解耦：即使用户停留在其它来源／页面，下载完成也能收到提示。
@MainActor
final class DownloadToastNotifier {
    @ObservationIgnored private let manager: DownloadManager
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var lastStates: [ComicIdentity: DownloadState] = [:]

    init(manager: DownloadManager) {
        self.manager = manager
    }

    /// 开始订阅；重复调用保持单条订阅。订阅随对象释放自动取消。
    func start() {
        guard task == nil else { return }

        let manager = manager
        task = Task { [weak self] in
            let stream = await manager.makeChangeStream()
            for await change in stream {
                if let summary = change.progress {
                    self?.handle(summary)
                }
            }
        }
    }

    /// 取消订阅：取消任务会让变更流终止，触发 `DownloadManager` 移除 continuation。
    deinit {
        task?.cancel()
    }

    /// 只在作品从「未完成」跨到「已完成」时提示一次，避免逐页进度重复弹出。
    private func handle(_ summary: DownloadedComicSummary) {
        let previous = lastStates[summary.identity]
        lastStates[summary.identity] = summary.state

        guard summary.state == .completed, previous != .completed else { return }

        ToastCenter.shared.show("《\(summary.title)》下载完成", type: .success)
    }
}

import Foundation

// MARK: - 变更广播

extension DownloadManager {
    /// 新建一条下载变更流；调用方负责在生命周期结束时取消订阅。
    func makeChangeStream() -> AsyncStream<DownloadChange> {
        let id = UUID()
        let (stream, continuation) = AsyncStream.makeStream(
            of: DownloadChange.self,
            bufferingPolicy: .bufferingNewest(1),
        )
        changeContinuations[id] = continuation
        // 弱引用自身：continuation 由本 actor 持有，强引用会形成 actor → continuation → actor 的环。
        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeContinuation(id) }
        }
        return stream
    }

    private func removeContinuation(_ id: UUID) {
        changeContinuations[id] = nil
    }

    /// 结构变化（作品集合或作品／章节状态变化）：递增版本并广播，消费方据此重读状态。
    func publishStructural(progress: DownloadedComicSummary? = nil) {
        structuralRevision &+= 1
        emit(progress: progress)
    }

    /// 纯进度更新（逐页）：不递增版本，只刷新可直接套用的展示（列表百分比）。
    func publishProgress(_ summary: DownloadedComicSummary) {
        emit(progress: summary)
    }

    private func emit(progress: DownloadedComicSummary?) {
        let change = DownloadChange(revision: structuralRevision, progress: progress)
        for continuation in changeContinuations.values {
            continuation.yield(change)
        }
    }
}

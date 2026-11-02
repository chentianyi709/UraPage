import Foundation

// MARK: - 暂停 / 继续 / 重试

extension DownloadManager {
    /// 暂停一个作品：停止该作品的封面和章节传输，保留已下载资产。
    func pause(_ comic: ComicIdentity) async {
        guard !isRemovingAll, !removingWorks.contains(comic) else { return }

        pausedWorks.insert(comic)
        pendingRuns.removeAll { $0 == comic }
        runControls[comic]?.stop()

        do {
            try await persistence().pauseWork(for: comic, now: Date())
        } catch {
            AppLogger.error(
                "下载暂停写入失败，source=\(comic.sourceID.rawValue)，errorType=\(String(reflecting: type(of: error)))",
                category: "App.Download",
            )
        }
        if var runtime = runtimes[comic] {
            for index in runtime.chapters.indices where runtime.chapters[index].state.canPause {
                runtime.chapters[index].state = .paused
            }
            if runtime.coverState.canPause {
                runtime.coverState = .paused
            }
            runtimes[comic] = runtime
        }
        publishStructural(progress: runtimes[comic].map(makeSummary(from:)))

        if let coverRun = coverRuns.removeValue(forKey: comic) {
            coverRun.task.cancel()
            await coverRun.task.value
        }
        if let task = activeRuns[comic]?.task {
            task.cancel()
            await task.value
        }
    }

    /// 继续一个作品：把暂停章节重新排队，并恢复缺失封面与章节的调度。
    func resume(_ comic: ComicIdentity) async {
        guard !isRemovingAll, !removingWorks.contains(comic) else { return }

        pausedWorks.remove(comic)
        do {
            try await persistence().requeueWork(for: comic, includeFailed: false, now: Date())
        } catch {
            AppLogger.error(
                "下载继续写入失败，source=\(comic.sourceID.rawValue)，errorType=\(String(reflecting: type(of: error)))",
                category: "App.Download",
            )
        }
        publishStructural()
        await startCoverTransfer(comic)
        await requestRun(comic)
    }

    /// 重试一个作品：把暂停与失败章节重新排队，并重试未保存的封面。
    func retry(_ comic: ComicIdentity) async {
        guard !isRemovingAll, !removingWorks.contains(comic) else { return }

        pausedWorks.remove(comic)
        do {
            try await persistence().requeueWork(for: comic, includeFailed: true, now: Date())
        } catch {
            AppLogger.error(
                "下载重试写入失败，source=\(comic.sourceID.rawValue)，errorType=\(String(reflecting: type(of: error)))",
                category: "App.Download",
            )
        }
        publishStructural()
        await startCoverTransfer(comic)
        await requestRun(comic)
    }
}

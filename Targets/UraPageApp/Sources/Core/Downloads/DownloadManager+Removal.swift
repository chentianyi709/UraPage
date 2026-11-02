import Foundation

// MARK: - 单作品删除

/// 删除下载时的调度冲突；页面据此区分「正在删除」与普通失败。
enum DownloadRemovalError: Error, Equatable, Sendable {
    /// 同一作品或全部下载已有删除／清空操作在处理中。
    case operationInProgress

    /// 删除前无法把在途任务稳定落为暂停状态，已放弃本次删除。
    case failedToStopTasks

    /// 删除入口的提示文案。
    var message: String {
        switch self {
        case .operationInProgress:
            "正在删除，请稍后重试"

        case .failedToStopTasks:
            "无法停止下载任务，请稍后重试"
        }
    }
}

extension DownloadManager {
    /// 删除一个作品的下载：停止在途封面／章节任务，删除全部记录，再尽力删除资产目录。
    ///
    /// 记录删除成功即视为删除完成；资产目录删除失败只会留下无入口的孤儿文件，由
    /// 「清理其他数据」回收，不再把记录恢复成指向缺失资产的 `completed` 状态。
    /// 删除前先阻断新的启动、等待已进入的启动收尾，再把在途状态落为暂停；记录删除失败时
    /// 恢复进入前的调度状态。资产 lease（离线阅读／导出）在停止任务前后各预检一次。
    func remove(_ comic: ComicIdentity) async throws {
        guard !isRemovingAll, enqueuingWorks[comic] == nil else {
            throw DownloadRemovalError.operationInProgress
        }
        guard !removingWorks.contains(comic) else { throw DownloadRemovalError.operationInProgress }
        guard await !assetStore.hasAssetLease(for: comic) else {
            throw DownloadAssetError.assetLeased
        }

        removingWorks.insert(comic)
        defer { removingWorks.remove(comic) }

        let wasPaused = pausedWorks.contains(comic)
        let wasPending = pendingRuns.contains(comic)
        let wasStarting = startingWorks.contains(comic)

        // 从调度中摘除：排队项移除；暂停意图挡住在途启动，并让协作循环尽快停止。
        pendingRuns.removeAll { $0 == comic }
        pausedWorks.insert(comic)

        // 先等已经通过入口检查的启动流程收尾；移除 `removingWorks` 后不会再有新的启动。
        await waitForStartingWork(comic)
        let hadActiveTransfers = coverRuns[comic] != nil
            || activeRuns[comic] != nil
            || wasStarting
        let resumeState = RemovalResumeState(
            wasPaused: wasPaused,
            wasPending: wasPending,
            wasStarting: wasStarting,
            hadActiveTransfers: hadActiveTransfers,
        )

        if hadActiveTransfers {
            // 与暂停一致：先把进行中／排队行落为「已暂停」（被取消的任务自身不写状态）。
            do {
                try await persistence().pauseWork(for: comic, now: Date())
            } catch {
                AppLogger.error(
                    "下载删除前停止任务写入失败，source=\(comic.sourceID.rawValue)，errorType=\(String(reflecting: type(of: error)))",
                    category: "App.Download",
                )
                await restoreAfterFailedRemoval(comic, state: resumeState)
                throw DownloadRemovalError.failedToStopTasks
            }
        }

        // 暂停落库成功后再取消任务，避免任务在删除失败恢复前把状态改回下载中。
        runControls[comic]?.stop()
        if let coverRun = coverRuns.removeValue(forKey: comic) {
            coverRun.task.cancel()
            await coverRun.task.value
        }
        if let task = activeRuns[comic]?.task {
            task.cancel()
            await task.value
        }

        // 停止任务期间可能刚登记新 lease（例如导出开始）；记录删除前再确认一次。
        guard await !assetStore.hasAssetLease(for: comic) else {
            await restoreAfterFailedRemoval(comic, state: resumeState)
            throw DownloadAssetError.assetLeased
        }

        do {
            try await persistence().removeWork(for: comic)
        } catch {
            await restoreAfterFailedRemoval(comic, state: resumeState)
            throw error
        }

        // 记录已删：资产删除失败只留下孤儿目录，不恢复记录，也不把删除判为失败。
        do {
            try await assetStore.removeComicDirectory(
                sourceID: comic.sourceID.rawValue,
                comicID: comic.comicID,
            )
        } catch {
            AppLogger.warning(
                "下载记录已删除，但资产目录删除失败，source=\(comic.sourceID.rawValue)，errorType=\(String(reflecting: type(of: error)))",
                category: "App.Download",
            )
        }

        discardRuntimeState(for: comic)
        pausedWorks.remove(comic)
        publishStructural()
    }

    /// 删除失败后恢复单个作品；记录与资产都保持进入前的状态，只需恢复被摘除的调度。
    ///
    /// 先释放删除锁：`requestRun` 会拒绝仍在 `removingWorks` 中的作品，若先恢复调度则不会生效。
    private func restoreAfterFailedRemoval(
        _ comic: ComicIdentity,
        state: RemovalResumeState,
    ) async {
        removingWorks.remove(comic)
        guard !state.wasPaused else { return }

        pausedWorks.remove(comic)
        if state.hadActiveTransfers {
            // 删除未生效：把取消过的任务放回调度，与「继续」同一路径。
            do {
                try await persistence().requeueWork(for: comic, includeFailed: false, now: Date())
            } catch {
                AppLogger.error(
                    "下载删除失败后恢复排队写入失败，source=\(comic.sourceID.rawValue)，errorType=\(String(reflecting: type(of: error)))",
                    category: "App.Download",
                )
            }
            await startCoverTransfer(comic)
        }
        if state.hadActiveTransfers || state.wasPending || state.wasStarting {
            await requestRun(comic)
            publishStructural()
        }
    }

    /// 删除成功后清掉该作品可能残留的运行时登记；正常收尾已清理时为空操作。
    private func discardRuntimeState(for comic: ComicIdentity) {
        if activeRuns.removeValue(forKey: comic) != nil {
            activeCounts[comic.sourceID] = max((activeCounts[comic.sourceID] ?? 0) - 1, 0)
        }
        runtimes[comic] = nil
        runControls[comic] = nil
        coverRuns[comic] = nil
    }
}

/// 单作品删除进入前的调度状态；三处失败回滚共用同一份入参，避免重复拼参数。
private struct RemovalResumeState {
    let wasPaused: Bool
    let wasPending: Bool
    let wasStarting: Bool
    let hadActiveTransfers: Bool
}

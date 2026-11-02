import Foundation

// MARK: - 清空全部与存储清理

extension DownloadManager {
    /// 清除全部下载：停止所有在途任务，删除全部记录，再尽力删除全部资产目录，返回删除的作品数。
    ///
    /// 有活动资产 lease 时在停止调度之前直接抛 `assetLeased`，不改动任何状态；其余失败会把
    /// 取消过的任务放回调度。记录删除成功后资产删除失败只留下孤儿目录，由「清理其他数据」回收，
    /// 不再保留指向已删记录的资产或恢复不可读取的完成记录。
    func removeAll() async throws -> Int {
        // 与其它清理入口对称：正在清理资产时不允许整体清空，避免删除记录与扫盘/删目录交叉。
        guard !isRemovingAll, !isCleaningDownloadStorage,
              removingWorks.isEmpty, enqueuingWorks.isEmpty
        else {
            throw DownloadRemovalError.operationInProgress
        }

        // 先置位再检查 lease：`await` 是 actor 重入点，两个并发清除不能同时通过门禁。
        isRemovingAll = true
        defer { isRemovingAll = false }

        guard await !assetStore.hasActiveAssetLease() else {
            throw DownloadAssetError.assetLeased
        }

        // 记录进入前的暂停意图与已知作品，失败时按原状恢复调度。
        let resumeState = RemoveAllResumeState(
            originallyPaused: pausedWorks,
            knownComics: Set(coverRuns.keys)
                .union(activeRuns.keys)
                .union(pendingRuns)
                .union(runtimes.keys)
                .union(startingWorks),
        )

        // 先阻断新的调度；已通过入口检查的启动流程在这里统一收尾。
        pausedWorks.formUnion(resumeState.knownComics)
        pendingRuns.removeAll()
        while let comic = startingWorks.first {
            await waitForStartingWork(comic)
        }

        // 一次事务暂停全部作品；写库失败时先恢复调度，不取消任何任务。
        do {
            try await persistence().pauseWorks(for: Array(resumeState.knownComics), now: Date())
        } catch {
            AppLogger.error(
                "清除下载前停止任务写入失败，errorType=\(String(reflecting: type(of: error)))",
                category: "App.Download",
            )
            await restoreAfterFailedRemoveAll(resumeState)
            throw DownloadRemovalError.failedToStopTasks
        }

        for control in runControls.values {
            control.stop()
        }
        let coverTasks = coverRuns.values.map(\.task)
        let runTasks = activeRuns.values.map(\.task)
        for task in coverTasks {
            task.cancel()
        }
        for task in runTasks {
            task.cancel()
        }
        for task in coverTasks {
            await task.value
        }
        for task in runTasks {
            await task.value
        }

        coverRuns.removeAll()
        activeRuns.removeAll()
        runControls.removeAll()
        runtimes.removeAll()
        activeCounts.removeAll()

        // 停止任务期间可能刚开始导出；删除记录前再确认一次，避免清掉导出正在读取的作品记录。
        guard await !assetStore.hasActiveAssetLease() else {
            await restoreAfterFailedRemoveAll(resumeState)
            throw DownloadAssetError.assetLeased
        }

        let removedWorks: Int
        do {
            removedWorks = try await persistence().removeAllWorks()
        } catch {
            await restoreAfterFailedRemoveAll(resumeState)
            throw error
        }

        // 记录已全部删除：资产删除失败只留下孤儿目录，不影响本次清除结果。
        do {
            try await assetStore.removeAllComicDirectories()
        } catch {
            AppLogger.warning(
                "下载记录已清除，但资产目录删除失败，errorType=\(String(reflecting: type(of: error)))",
                category: "App.Download",
            )
        }

        // 记录已全部删除，残留的暂停意图不再有对应作品。
        pausedWorks.removeAll()
        publishStructural()
        return removedWorks
    }

    /// 下载资产的实际占用字节数，供设置页「清除下载记录」展示；只读查询，不参与清除门禁。
    ///
    /// 与 `removeAll()` 的删除范围一致，因此也是这次清除会释放的空间。
    nonisolated func assetUsageBytes() async throws -> Int {
        try await assetStore.assetUsageBytes()
    }

    /// 删除无法读取的下载记录，并连带删除这些作品已不可访问的资产目录。
    ///
    /// 这些作品没有可进入的入口（列表不可见、离线详情加载失败）；持久化记录直接删除，
    /// 资产目录删除仍受 `removeComicDirectory` 的 lease 门禁约束：正常情况下不存在 lease；
    /// 若仍被占用（异常情况），该目录删除失败、只记录警告，由孤儿资产清理兜底。
    func removeUnreadableRecords() async throws -> UnreadableDownloadRecords {
        guard !isRemovingAll, !isCleaningDownloadStorage else {
            throw DownloadRemovalError.operationInProgress
        }

        // 进入删除阶段后拒绝新入队；已经开始的入队可能随后写入同一作品的新记录和资产，
        // 这些身份不能按旧记录删除，否则会误删刚开始的新下载。
        isCleaningDownloadStorage = true
        defer { isCleaningDownloadStorage = false }
        let enqueuingIdentities = Set(enqueuingWorks.keys.map {
            DownloadAssetIdentity(sourceID: $0.sourceID.rawValue, comicID: $0.comicID)
        })

        let result = try await persistence().removeUnreadableRecords()
        for work in result.removedWorkIdentities {
            let identity = DownloadAssetIdentity(sourceID: work.sourceID, comicID: work.comicID)
            guard !enqueuingIdentities.contains(identity) else {
                AppLogger.warning(
                    "无法读取记录的旧资产跳过清理：作品正在重新入队，source=\(work.sourceID)",
                    category: "App.Download",
                )
                continue
            }

            do {
                try await assetStore.removeComicDirectory(sourceID: work.sourceID, comicID: work.comicID)
            } catch {
                AppLogger.warning(
                    "无法读取记录的资产清理失败，source=\(work.sourceID)，errorType=\(String(reflecting: type(of: error)))",
                    category: "App.Download",
                )
            }
        }
        return result.records
    }

    /// 统计没有对应下载记录的孤立资产目录（设置页「清理其他数据」预览）。
    func orphanedAssetCount() async throws -> Int {
        guard !isRemovingAll, !isCleaningDownloadStorage else {
            throw DownloadRemovalError.operationInProgress
        }

        let known = try await knownAssetIdentities()
        return try await assetStore.orphanedComicDirectories(known: known).count
    }

    /// 删除没有对应下载记录的孤立资产目录，返回实际删除数量；单个目录失败只记录日志。
    ///
    /// 身份快照与扫盘期间拒绝新入队，避免把新写入记录、正在创建目录的作品误判为孤儿；
    /// 入队事务期间的作品身份也计入已知集合。仍被离线阅读／导出 lease 占用的目录会被拒绝，
    /// 留待下次清理。
    func removeOrphanedAssets() async throws -> Int {
        guard !isRemovingAll, !isCleaningDownloadStorage else {
            throw DownloadRemovalError.operationInProgress
        }

        // 先置位再取身份与扫盘：新入队会在这里被拒绝；已开始的入队由 known 集合保护。
        isCleaningDownloadStorage = true
        defer { isCleaningDownloadStorage = false }

        let known = try await knownAssetIdentities()
        let directories = try await assetStore.orphanedComicDirectories(known: known)

        var removedCount = 0
        for directory in directories {
            do {
                try await assetStore.removeOrphanedDirectory(at: directory)
                removedCount += 1
            } catch {
                AppLogger.warning(
                    "孤立下载资产清理失败，name=\(directory.lastPathComponent)，errorType=\(String(reflecting: type(of: error)))",
                    category: "App.Download",
                )
            }
        }
        return removedCount
    }

    /// 当前仍应受记录保护的作品身份：正在入队的作品＋持久化中的全部作品。
    ///
    /// `enqueuingWorks` 必须在第一个 `await` 之前快照：等待持久化期间完成的入队会把自己移出该表，
    /// 若等持久化返回后再读，就可能漏掉它刚写入的记录，把新创建的资产目录误判为孤儿。
    private func knownAssetIdentities() async throws -> [DownloadAssetIdentity] {
        let enqueuing = enqueuingWorks.keys.map {
            DownloadAssetIdentity(sourceID: $0.sourceID.rawValue, comicID: $0.comicID)
        }
        var known = try await persistence().allAssetIdentities()
        known.append(contentsOf: enqueuing)
        return known
    }

    /// 清空失败后恢复全部作品：先释放清空锁并还原暂停集合，再按进入前的暂停意图重启调度。
    ///
    /// `requestRun` 会拒绝 `isRemovingAll` 或 `pausedWorks` 中的作品，因此必须先还原这两项。
    private func restoreAfterFailedRemoveAll(_ state: RemoveAllResumeState) async {
        isRemovingAll = false
        pausedWorks = state.originallyPaused
        for comic in state.knownComics where !state.originallyPaused.contains(comic) {
            do {
                try await persistence().requeueWork(for: comic, includeFailed: false, now: Date())
            } catch {
                AppLogger.error(
                    "清除下载失败后恢复排队写入失败，source=\(comic.sourceID.rawValue)，errorType=\(String(reflecting: type(of: error)))",
                    category: "App.Download",
                )
            }
            await startCoverTransfer(comic)
            await requestRun(comic)
        }
        publishStructural()
    }
}

/// 清空全部进入前的调度状态；三处失败回滚共用同一份入参。
private struct RemoveAllResumeState {
    let originallyPaused: Set<ComicIdentity>
    let knownComics: Set<ComicIdentity>
}

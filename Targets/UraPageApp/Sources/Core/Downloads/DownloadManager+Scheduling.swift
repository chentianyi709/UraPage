import Foundation

// MARK: - 调度与生命周期

extension DownloadManager {
    func requestRun(_ comic: ComicIdentity) async {
        guard !isRemovingAll, !removingWorks.contains(comic),
              !hostRestartingWorks.contains(comic)
        else { return }

        if activeRuns[comic] != nil || startingWorks.contains(comic) {
            // 已有任务在跑或在启动：登记待运行，等当前任务收尾后由 pump 接力（用于暂停后继续等场景）。
            if !pausedWorks.contains(comic), !pendingRuns.contains(comic) {
                pendingRuns.append(comic)
            }
            return
        }
        guard !pausedWorks.contains(comic) else { return }

        if reserveStarting(comic) {
            await beginRun(comic)
        } else if !pendingRuns.contains(comic) {
            pendingRuns.append(comic)
        }
    }

    func pump() async {
        var index = 0
        while index < pendingRuns.count {
            let comic = pendingRuns[index]
            if reserveStarting(comic) {
                pendingRuns.remove(at: index)
                await beginRun(comic)
            } else {
                index += 1
            }
        }
    }

    /// 占用一个启动名额并登记启动；名额已满或当前状态不允许时返回 `false`。
    ///
    /// 只在 actor 内同步执行：名额判定与 `startingWorks` 登记之间没有挂起点，
    /// 并发的 `requestRun`／`pump` 不会因为 `activeCounts` 尚未递增而一起越过上限。
    /// 成功后由 `beginRun` 接手异步准备，它的 `defer` 统一归还登记。
    private func reserveStarting(_ comic: ComicIdentity) -> Bool {
        guard activeRuns[comic] == nil, !startingWorks.contains(comic),
              !pausedWorks.contains(comic), !removingWorks.contains(comic),
              !hostRestartingWorks.contains(comic), !isRemovingAll
        else { return false }

        let sourceID = comic.sourceID
        let startingCount = startingWorks.filter { $0.sourceID == sourceID }.count
        guard (activeCounts[sourceID] ?? 0) + startingCount < workLimitPerSource else {
            return false
        }

        startingWorks.insert(comic)
        return true
    }

    private func beginRun(_ comic: ComicIdentity) async {
        // 名额已由 `reserveStarting` 同步登记；只允许本文件的 requestRun／pump 调用。
        guard startingWorks.contains(comic) else { return }

        defer {
            startingWorks.remove(comic)
            if let waiters = startingWaiters.removeValue(forKey: comic) {
                for waiter in waiters {
                    waiter.resume()
                }
            }
        }

        let display: DownloadWorkDisplay?
        let records: [ChapterDownloadRecord]
        do {
            let persistence = try await persistence()
            display = try await persistence.workDisplay(for: comic)
            records = try await persistence.chapterRecords(for: comic)
        } catch {
            AppLogger.error(
                "下载任务启动时读取作品记录失败，source=\(comic.sourceID.rawValue)，errorType=\(String(reflecting: type(of: error)))",
                category: "App.Download",
            )
            return
        }
        guard !pausedWorks.contains(comic),
              !removingWorks.contains(comic),
              !isRemovingAll
        else { return }
        guard let display else {
            AppLogger.error("下载任务缺少作品快照，source=\(comic.sourceID.rawValue)", category: "App.Download")
            return
        }

        let chapters = records.map {
            ChapterRuntime(
                identity: $0.identity,
                state: $0.state,
                totalUnitCount: nil,
                completedUnitCount: 0,
            )
        }
        // 作品运行只负责章节；封面由独立封面任务处理，不在此等待也不占本运行的名额。
        guard chapters.contains(where: { $0.state == .queued }) else {
            publishStructural()
            return
        }

        runControls[comic] = RunControl()
        let runtime = WorkRuntime(
            comic: comic,
            title: display.title,
            authors: display.authors,
            cover: display.cover,
            coverState: display.coverState,
            chapters: chapters,
            chapterCount: records.count,
            completedChapterCount: records.filter { $0.state == .completed }.count,
        )
        runtimes[comic] = runtime
        activeCounts[comic.sourceID, default: 0] += 1

        let token = UUID()
        let task = Task {
            await self.downloadAll(comic)
            await self.finishRun(comic, token: token)
        }
        activeRuns[comic] = RunState(token: token, task: task)
        publishStructural(progress: makeSummary(from: runtime))
    }

    private func finishRun(_ comic: ComicIdentity, token: UUID) async {
        guard let state = activeRuns[comic], state.token == token else { return }

        // 收尾事件携带该作品最后一次快照，避免完成态被后续其它作品的事件覆盖而丢失。
        let summary = runtimes[comic].map(makeSummary(from:))
        activeRuns[comic] = nil
        runtimes[comic] = nil
        runControls[comic] = nil
        activeCounts[comic.sourceID] = max((activeCounts[comic.sourceID] ?? 0) - 1, 0)
        publishStructural(progress: summary)
        await pump()
    }

    /// 当前运行是否已被要求停止（用户暂停或 Host 重启）；两种停止原因都让协作循环尽快退出。
    func isRunStopped(_ comic: ComicIdentity) -> Bool {
        runControls[comic]?.isStopped ?? false
    }

    /// 等待一个启动中的作品完成启动流程；删除／清空在暂停落库前调用，避免启动登记在删除之后。
    func waitForStartingWork(_ comic: ComicIdentity) async {
        guard startingWorks.contains(comic) else { return }

        await withCheckedContinuation { continuation in
            startingWaiters[comic, default: []].append(continuation)
        }
    }
}

import Foundation

// MARK: - 服务器线路切换

extension DownloadManager {
    /// 启动按来源订阅 Host 切换成功事件；由 App 启动任务在下载对账前调用一次。
    ///
    /// 事件只表示服务器线路已切换，图源等其它设置变更不会发布到这里。
    func startHostChangeObservation() {
        guard hostObservationTasks.isEmpty else { return }

        for sourceID in ComicSourceID.allCases {
            let runtime = catalog.runtime(for: sourceID)
            let task = Task { [weak self] in
                let stream = await runtime.hostChangeStream()
                for await _ in stream {
                    guard let self else { return }

                    await handleHostChange(sourceID: sourceID)
                }
            }
            hostObservationTasks.append(task)
        }
    }

    /// 线路切换后重启该来源所有当前运行中的作品；排队与尚未启动的作品轮到时会自然使用新 Host。
    private func handleHostChange(sourceID: ComicSourceID) async {
        hostGenerations[sourceID, default: 0] &+= 1
        AppLogger.debug(
            "下载收到服务器线路切换，source=\(sourceID.rawValue)，hostGeneration=\(hostGenerations[sourceID] ?? 0)",
            category: "App.Download",
        )

        let comics = Set(activeRuns.keys)
            .union(coverRuns.keys)
            .filter {
                $0.sourceID == sourceID
                    && !pausedWorks.contains($0)
                    && !removingWorks.contains($0)
            }
        for comic in comics {
            await restartWorkAfterHostChange(comic)
        }
    }

    /// 停止一个作品的旧任务，重排其当前下载中章节，再按新 Host 重新开始。
    ///
    /// 旧 run 完全结束后才重排并启动新 run：章节句柄与页面描述在打开时固定，不能把旧 Host 的在途任务
    /// 直接接给新 run。已完成页保留在 manifest 中，新 run 重新打开章节后只补缺失页；
    /// 事件前已失败／暂停的章节不重排。
    private func restartWorkAfterHostChange(_ comic: ComicIdentity) async {
        guard !removingWorks.contains(comic), !hostRestartingWorks.contains(comic) else { return }

        // 同一来源连续切换时，后来的事件跳过正在重启的作品：本次新 run 必然在事件之后才启动并使用最新 Host。
        hostRestartingWorks.insert(comic)
        defer { hostRestartingWorks.remove(comic) }

        let hadActiveRun = activeRuns[comic] != nil
        if hadActiveRun {
            // 旧 run 收尾时 pump 不会立刻启动新 run。
            runControls[comic]?.stop()
        }

        let runTask = activeRuns[comic]?.task

        // 封面与章节任务相互独立，先取消旧封面，避免旧 Host 的迟到结果写回。
        // 旧任务结束时按 token 自行清理 coverRuns 登记；等待期间登记仍在，阻止 resume 等入口再启动封面任务。
        if let coverRun = coverRuns[comic] {
            coverRun.task.cancel()
            await coverRun.task.value
        }

        if let runTask {
            runTask.cancel()
            await runTask.value
        }

        guard !pausedWorks.contains(comic), !removingWorks.contains(comic), !isRemovingAll else {
            return
        }

        var requeuedChapters: [ChapterIdentity] = []
        do {
            requeuedChapters = try await persistence().requeueDownloadingChapters(for: comic, now: Date())
            if let chapter = requeuedChapters.first {
                AppLogger.debug(
                    "Host 切换重排下载中章节，comicID=\(comic.comicID)，chapterID=\(chapter.chapterID)，count=\(requeuedChapters.count)",
                    category: "App.Download",
                )
            }
        } catch {
            AppLogger.error(
                "Host 切换重排章节写入失败，source=\(comic.sourceID.rawValue)，errorType=\(String(reflecting: type(of: error)))",
                category: "App.Download",
            )
        }

        do {
            try await persistence().requeueDownloadingCover(for: comic, now: Date())
        } catch {
            AppLogger.error(
                "Host 切换重排封面写入失败，source=\(comic.sourceID.rawValue)，errorType=\(String(reflecting: type(of: error)))",
                category: "App.Download",
            )
        }
        await startCoverTransfer(comic)
        publishStructural()

        guard hadActiveRun || !requeuedChapters.isEmpty else { return }

        hostRestartingWorks.remove(comic)
        pendingRuns.removeAll { $0 == comic }
        await requestRun(comic)
    }
}

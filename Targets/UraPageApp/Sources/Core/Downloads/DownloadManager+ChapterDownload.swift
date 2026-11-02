import Foundation

// MARK: - 章节下载

extension DownloadManager {
    /// 按目录顺序逐章下载；用户暂停、Host 重启或没有排队章节时结束本轮。
    func downloadAll(_ comic: ComicIdentity) async {
        while true {
            guard let runtime = runtimes[comic], !isRunStopped(comic) else { return }
            guard let index = runtime.chapters.firstIndex(where: { $0.state == .queued }) else {
                return
            }
            guard await downloadChapter(comic, index: index) else { return }
        }
    }

    /// 下载一个章节：打开章节 → 逐批取分页并补下缺失页（每页落盘即记入清单、按节流提交）→ 提交最终状态。
    ///
    /// 进度按“单位”计：章节信息（含首批）1 个、后续每个分页请求 1 个、每页图片 1 个；
    /// 命中缓存或已下载的页同样算完成单位。单位总数在打开章节后即可确定。
    ///
    /// 返回 `true` 表示本章已给出结论（完成／失败），调度继续下一章；
    /// 返回 `false` 表示本轮中止（用户暂停、Host 重启、已被接管或启动写入失败），由 `downloadAll` 结束。
    private func downloadChapter(_ comic: ComicIdentity, index: Int) async -> Bool {
        guard let runtime = runtimes[comic], runtime.chapters.indices.contains(index) else { return false }

        let identity = runtime.chapters[index].identity
        let jobID = UUID()
        // 在打开章节前固定 Host 代次：旧 run 的页传输只与同代次合并，不污染切换后的新任务。
        let hostGeneration = hostGenerations[comic.sourceID, default: 0]
        guard await beginChapter(identity, comic: comic, index: index, jobID: jobID) else {
            return false
        }

        do {
            let handle = try await openChapter(identity)
            guard !isRunStopped(comic) else { return false }

            // 章节信息（含首批）先记 1 个单位；分页请求数与页数决定分母。
            let totalPageCount = handle.content.totalPageCount
            let batchSize = handle.pageBatchSize
            let batchCount = Self.batchCount(totalPageCount: totalPageCount, batchSize: batchSize)
            let totalUnitCount = 1 + max(batchCount - 1, 0) + totalPageCount

            // 空章节没有需要下载的页：写空清单后直接完成，阅读页按「当前章节没有图片」展示。
            guard totalPageCount > 0 else {
                guard setChapterUnits(comic: comic, index: index, completed: 1, total: 1)
                else { return false }

                let saved = await saveManifest(identity: identity, totalPageCount: 0, entries: [:])
                await finishChapter(
                    identity,
                    comic: comic,
                    index: index,
                    jobID: jobID,
                    state: saved ? .completed : .failed,
                )
                return true
            }

            // 分母已确定、正在核对已下载内容：先发布 0 计数，进度环显示「检查中」。
            guard setChapterUnits(comic: comic, index: index, completed: 0, total: totalUnitCount)
            else { return false }

            // 续传只信任 manifest 中登记的页面；页面字节不重新读取或校验。
            // 核对完成后把章节信息与已登记的页一并计入，重启续传时直接回到接近原来的百分比、不先闪 0%。
            let entries = try await loadResumedEntries(for: identity)
            guard setChapterUnits(
                comic: comic,
                index: index,
                completed: 1 + entries.count,
                total: totalUnitCount,
            ) else { return false }

            var commit = ChapterManifestCommit(entries: entries)
            var seenPageCount = 0
            var hadFailure = false

            for batchIndex in 0 ..< batchCount {
                let pageOffset = batchIndex * (batchSize ?? max(totalPageCount, 1))
                let pages = try await handle.pages(containing: pageOffset)
                guard !isRunStopped(comic) else { return false }

                // 首批随章节信息取得，不再单独计数；后续每批算一个分页单位。
                if batchIndex > 0, !advanceChapterUnit(comic: comic, index: index) {
                    return false
                }
                seenPageCount += pages.count

                let pending = pages.filter { commit.entries[$0.identity.pageID]?.index != $0.index }

                if !pending.isEmpty {
                    let result = await downloadPages(
                        pending,
                        handle: handle,
                        comic: comic,
                        chapterIndex: index,
                        hostGeneration: hostGeneration,
                        commit: commit,
                    )
                    commit = result.commit
                    hadFailure = result.hadFailure || hadFailure
                }

                // 批次边界强制提交：分页请求对应的进度一定写盘，不依赖节流窗口。
                commit = await commitManifest(
                    commit,
                    identity: identity,
                    totalPageCount: totalPageCount,
                    force: true,
                )
            }

            guard !isRunStopped(comic) else { return false }

            // 章节结束前必须有一次成功提交：清单是页的唯一索引，写不进去的章节不能算完成。
            commit = await commitManifest(
                commit,
                identity: identity,
                totalPageCount: totalPageCount,
                force: true,
            )

            // 来源清单缺少页或序号不连续时，即使全部页都下完也不算完成，避免把缺页标成已完成。
            let hasMissingPageSlots = seenPageCount != totalPageCount
            let state: DownloadState = hadFailure || !commit.isFullyCommitted || hasMissingPageSlots
                ? .failed
                : .completed
            await finishChapter(identity, comic: comic, index: index, jobID: jobID, state: state)
            return true
        } catch {
            guard !isRunStopped(comic) else { return false }

            await failChapter(identity, comic: comic, index: index, jobID: jobID)
            return true
        }
    }

    /// 记录章节开始并切到「下载中」；运行已停止、已被接管或写入失败时返回 `false`。
    private func beginChapter(
        _ identity: ChapterIdentity,
        comic: ComicIdentity,
        index: Int,
        jobID: UUID,
    ) async -> Bool {
        let didStart: Bool
        do {
            didStart = try await persistence().startChapter(identity, jobID: jobID, now: Date())
        } catch {
            AppLogger.error(
                "下载章节启动状态写入失败，chapterID=\(identity.chapterID)，errorType=\(String(reflecting: type(of: error)))",
                category: "App.Download",
            )
            return false
        }
        guard didStart, !isRunStopped(comic),
              var runtime = runtimes[comic],
              runtime.chapters.indices.contains(index)
        else {
            // 已被暂停或其它任务接管，跳过本章。
            return false
        }

        runtime.chapters[index].state = .downloading
        runtimes[comic] = runtime
        publishStructural(progress: makeSummary(from: runtime))
        return true
    }

    /// 设置当前章节的单位分母与已计数；运行已停止或运行时失效时返回 `false`。
    private func setChapterUnits(
        comic: ComicIdentity,
        index: Int,
        completed: Int,
        total: Int,
    ) -> Bool {
        guard !isRunStopped(comic),
              var runtime = runtimes[comic],
              runtime.chapters.indices.contains(index)
        else { return false }

        runtime.chapters[index].totalUnitCount = total
        runtime.chapters[index].completedUnitCount = completed
        runtimes[comic] = runtime
        publishStructural(progress: makeSummary(from: runtime))
        return true
    }

    /// 章节进度前进一个单位并广播；运行已停止或运行时失效时返回 `false`。
    func advanceChapterUnit(comic: ComicIdentity, index: Int) -> Bool {
        guard !isRunStopped(comic),
              var runtime = runtimes[comic],
              runtime.chapters.indices.contains(index)
        else { return false }

        runtime.chapters[index].completedUnitCount += 1
        runtimes[comic] = runtime
        publishProgress(makeSummary(from: runtime))
        return true
    }

    /// 读取 manifest 中登记的页面索引；清单缺失或损坏时返回空（按重下处理）。
    private func loadResumedEntries(for identity: ChapterIdentity) async throws
        -> [String: DownloadManifest.PageEntry] {
        let manifest: DownloadManifest?
        do {
            manifest = try await assetStore.loadManifest(for: identity)
        } catch DownloadAssetError.corruptedManifest {
            AppLogger.warning(
                "下载章节清单损坏，将重新下载，chapterID=\(identity.chapterID)",
                category: "App.Download",
            )
            manifest = nil
        }

        guard let manifest else { return [:] }

        return Dictionary(
            uniqueKeysWithValues: manifest.pages.map { ($0.pageID, $0) },
        )
    }

    /// 提交章节最终状态并广播；持久化写入失败或 jobID 已失效时不改变运行时状态。
    ///
    /// Host 重启会先把章节退回排队；旧 run 随后的完成／失败提交必须被拒绝，
    /// 否则会把重新入队的章节覆盖成失败或完成。
    private func finishChapter(
        _ identity: ChapterIdentity,
        comic: ComicIdentity,
        index: Int,
        jobID: UUID,
        state: DownloadState,
    ) async {
        let didWrite: Bool
        do {
            didWrite = try await persistence().finishChapter(
                identity,
                jobID: jobID,
                state: state,
                now: Date(),
            )
        } catch {
            AppLogger.error(
                "下载章节最终状态写入失败，chapterID=\(identity.chapterID)，errorType=\(String(reflecting: type(of: error)))",
                category: "App.Download",
            )
            return
        }
        guard didWrite else { return }

        // 完成提交推进了持久化投影的完成数；先对齐运行时计数缓存再广播章节状态。
        if state == .completed {
            await refreshRuntimeCounts(for: comic)
        }

        updateChapterStateAfterRun(comic: comic, index: index, state: state)
    }

    /// 标记章节失败并广播；保留已落盘页供重试补齐，jobID 已失效时不改写运行时状态。
    private func failChapter(
        _ identity: ChapterIdentity,
        comic: ComicIdentity,
        index: Int,
        jobID: UUID,
    ) async {
        let didWrite: Bool
        do {
            didWrite = try await persistence().finishChapter(
                identity,
                jobID: jobID,
                state: .failed,
                now: Date(),
            )
        } catch {
            AppLogger.error(
                "下载章节失败状态写入失败，chapterID=\(identity.chapterID)，errorType=\(String(reflecting: type(of: error)))",
                category: "App.Download",
            )
            return
        }
        guard didWrite else { return }

        updateChapterStateAfterRun(comic: comic, index: index, state: .failed)
    }

    private func updateChapterStateAfterRun(comic: ComicIdentity, index: Int, state: DownloadState) {
        guard var runtime = runtimes[comic], runtime.chapters.indices.contains(index) else { return }

        runtime.chapters[index].state = state
        runtimes[comic] = runtime
        publishStructural(progress: makeSummary(from: runtime))
    }

    /// 打开指定章节；Reader 与下载共用同一来源章节入口。
    private func openChapter(_ identity: ChapterIdentity) async throws -> any SourceOpenedChapter {
        try await catalog.runtime(for: identity.comic.sourceID)
            .chapterContentService()
            .openChapter(identity)
    }

    /// 分页批次数：非分页来源为 1（整章随章节信息一次取得）。
    private static func batchCount(totalPageCount: Int, batchSize: Int?) -> Int {
        guard let batchSize, batchSize > 0 else { return 1 }

        return max((totalPageCount + batchSize - 1) / batchSize, 1)
    }
}

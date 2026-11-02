import Foundation

// MARK: - 进度投影

extension DownloadManager {
    /// 由运行时章节与封面状态生成本次变更的作品进度快照。
    ///
    /// 计数以持久化投影为准（运行时缓存）；快照建立后新入队的章节不在运行时列表中，
    /// 按投影补 `.queued` 参与状态聚合，保证状态、计数与列表读取口径一致。
    func makeSummary(from runtime: WorkRuntime) -> DownloadedComicSummary {
        let missingCount = max(runtime.chapterCount - runtime.chapters.count, 0)
        let states = runtime.chapters.map(\.state)
            + Array(repeating: DownloadState.queued, count: missingCount)
        return DownloadedComicSummary(
            identity: runtime.comic,
            title: runtime.title,
            authors: runtime.authors,
            cover: runtime.cover,
            state: DownloadedComicSummary.aggregateState(states, coverState: runtime.coverState),
            completedChapterCount: runtime.completedChapterCount,
            chapterCount: runtime.chapterCount,
            progress: progress(for: runtime),
            updatedAt: Date(),
        )
    }

    /// 把运行时的计数缓存对齐到持久化投影并广播。
    ///
    /// 运行时存续期间能改变章节计数的提交只有入队新增章节与章节完成两处
    /// （暂停／继续／重试／失败只在非完成态之间换状态，不改变计数），提交后各调用一次。
    /// 入队还可能落在「作品正在启动、运行时尚未登记」的窗口：此时也继续读取，
    /// 读取返回后按最新运行时状态对齐，避免启动窗口内的追加丢失。
    /// 读取失败只记录日志、缓存保持旧值，等下一次对齐或运行收尾后回到投影。
    func refreshRuntimeCounts(for comic: ComicIdentity) async {
        guard runtimes[comic] != nil || startingWorks.contains(comic) else { return }

        do {
            guard let projection = try await persistence().summary(for: comic),
                  var runtime = runtimes[comic]
            else { return }

            runtime.chapterCount = projection.chapterCount
            runtime.completedChapterCount = projection.completedChapterCount
            runtimes[comic] = runtime
            publishStructural(progress: makeSummary(from: runtime))
        } catch {
            AppLogger.error(
                "下载计数对齐读取失败，source=\(comic.sourceID.rawValue)，errorType=\(String(reflecting: type(of: error)))",
                category: "App.Download",
            )
        }
    }

    /// 运行中的进度形态；没有正在处理的章节时返回 `nil`（只剩封面，或未在运行）。
    ///
    /// 单章与多章口径一致：百分比只看当前章节的单位进度，封面不计入分母，只参与「作品是否完成」。
    /// 打开章节前是「准备中」，打开后核对已下载内容时是「检查中」。
    private func progress(for runtime: WorkRuntime) -> DownloadedComicSummary.Progress? {
        if runtime.chapters.count == 1, let chapter = runtime.chapters.first {
            guard chapter.state == .downloading else { return nil }
            guard let total = chapter.totalUnitCount, total > 0 else { return .preparing }
            guard chapter.completedUnitCount > 0 else { return .checking }

            return .units(min(max(Double(chapter.completedUnitCount) / Double(total), 0), 1))
        }

        guard let active = runtime.chapters.first(where: { $0.state == .downloading }) else {
            return nil
        }
        guard let total = active.totalUnitCount, total > 0 else { return .preparing }
        guard active.completedUnitCount > 0 else { return .checking }

        return .units(min(max(Double(active.completedUnitCount) / Double(total), 0), 1))
    }
}

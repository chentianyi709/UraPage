import Foundation

// MARK: - 读取

extension DownloadManager {
    /// 一页下载记录聚合：未完成组在前、已完成组在后；
    /// 运行中的作品用运行时快照替换持久化投影（排序规则见 `DownloadPersistence.summariesPage`）。
    ///
    /// `limit` 是目标条数：列表刷新按已加载窗口传入（至少 `summariesPageSize`），
    /// 分页追加使用默认页大小。
    func summariesPage(
        after cursor: DownloadedComicCursor?,
        limit: Int = summariesPageSize,
    ) async throws -> DownloadedComicPage {
        let page = try await persistence().summariesPage(after: cursor, limit: limit)
        return DownloadedComicPage(
            items: page.items.map(currentSummary),
            nextCursor: page.nextCursor,
        )
    }

    /// 读取离线详情（作品行列＋冷字段组装）与全部章节元信息；只有作品已完成时才返回。
    ///
    /// 只信任持久化的完成状态，不扫描章节 manifest 或图片文件；部分章节／图片
    /// 失败的作品为 `failed`，需要先在下载记录重试补齐。
    func offlineDetail(for comic: ComicIdentity) async throws -> DownloadedComicDetailRecord? {
        try await persistence().offlineRecord(for: comic)
    }

    /// 单个作品的当前聚合快照；运行中的作品用运行时快照替换持久化投影。
    ///
    /// 读取失败向上抛出：调用方必须区分“没有下载记录”和“本地记录读取失败”，
    /// 不能用一个 `nil` 同时表达两种结果。
    func summary(for comic: ComicIdentity) async throws -> DownloadedComicSummary? {
        try await persistence().summary(for: comic).map(currentSummary)
    }

    /// 详情页下载状态：作品聚合状态（运行时优先）与各章节条目；由一次持久化调用取回。
    ///
    /// 读取失败向上抛出，由页面状态 owner 记录失败并保留已知状态；
    /// 不返回空数组伪装成“没有下载”。
    func downloadStatus(for comic: ComicIdentity) async throws -> (
        workState: DownloadState?,
        items: [DownloadChapterSelectionItem],
    ) {
        let status = try await persistence().downloadStatus(for: comic)
        return (
            status.summary.map(currentSummary)?.state,
            status.chapters.map(\.selectionItem),
        )
    }

    /// 统计无法读取的下载记录（设置页「清理其他数据」预览）。
    func unreadableRecords() async throws -> UnreadableDownloadRecords {
        try await persistence().unreadableRecords()
    }

    private func currentSummary(_ summary: DownloadedComicSummary) -> DownloadedComicSummary {
        if let runtime = runtimes[summary.identity] {
            return makeSummary(from: runtime)
        }
        if pendingRuns.contains(summary.identity) || startingWorks.contains(summary.identity) {
            return summary.replacingState(.queued)
        }

        return summary
    }
}

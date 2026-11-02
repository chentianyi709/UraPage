import Foundation
import SwiftData

// MARK: - 分页

extension DownloadPersistence {
    /// 一页作品下载聚合：未完成组在前、已完成组在后；组内按排序时间倒序
    /// （未完成＝最近一次入队时间，已完成＝完成时间）。
    ///
    /// 排序键只在**入队**（刷新未完成组时间）与**首次完成**（进入已完成组并写入完成时间）时变化：
    /// 开始、暂停、继续或失败都不重排，因此下载过程中顺序稳定；完成的作品离开未完成组后，
    /// 不会再把入队更早的未完成作品挤到已完成之后。
    /// 只读作品行的聚合投影，不逐作品查章节行。`limit` 是目标条数，由调用方按已加载窗口给出
    /// （页大小定义在 `DownloadManager.summariesPageSize`），避免页面按固定页长循环读取。
    func summariesPage(
        after cursor: DownloadedComicCursor?,
        limit: Int,
    ) throws -> DownloadedComicPage {
        let pageSize = max(limit, 1)
        let sortBy = [
            SortDescriptor(\StoredDownloadedComic.sortGroup, order: .forward),
            SortDescriptor(\StoredDownloadedComic.sortAt, order: .reverse),
            SortDescriptor(\StoredDownloadedComic.identityKey, order: .reverse),
        ]
        var descriptor: FetchDescriptor<StoredDownloadedComic>
        if let cursor {
            let sortGroup = cursor.sortGroup
            let sortAt = cursor.sortAt
            let identityKey = cursor.identityKey
            descriptor = FetchDescriptor(
                predicate: #Predicate { work in
                    work.sortGroup > sortGroup
                        || (work.sortGroup == sortGroup
                            && (work.sortAt < sortAt
                                || (work.sortAt == sortAt && work.identityKey < identityKey)))
                },
                sortBy: sortBy,
            )
        } else {
            descriptor = FetchDescriptor(sortBy: sortBy)
        }
        // 多取一条用于判断是否还有下一页。
        descriptor.fetchLimit = pageSize + 1

        let fetched = try modelContext.fetch(descriptor)
        let works = Array(fetched.prefix(pageSize))
        // 列表只读作品行的聚合投影；单项无法读取时跳过该行，不作废整页可用数据。
        var unreadableCount = 0
        let items: [DownloadedComicSummary] = works.compactMap { work in
            do {
                return try makeSummary(work: work)
            } catch {
                unreadableCount += 1
                return nil
            }
        }
        if unreadableCount > 0 {
            AppLogger.warning(
                "下载记录存在无法读取的行，已跳过，count=\(unreadableCount)",
                category: "App.Download",
            )
        }
        let nextCursor = fetched.count > pageSize ? works.last.map {
            DownloadedComicCursor(
                sortGroup: $0.sortGroup,
                sortAt: $0.sortAt,
                identityKey: $0.identityKey,
            )
        } : nil
        return DownloadedComicPage(items: items, nextCursor: nextCursor)
    }
}

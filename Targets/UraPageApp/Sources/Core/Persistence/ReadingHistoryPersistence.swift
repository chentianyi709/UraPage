import Foundation
import SwiftData

/// 在独立 SwiftData executor 上处理阅读记录；只向上层返回 Sendable 值。
@ModelActor
actor ReadingHistoryPersistence {
    private static let pageSize = 30
    private var revision: UInt64 = 0

    /// 逐行解码封面引用用的解码器：一页 30 行不必每行新建；只在 actor 内同步使用。
    private let jsonDecoder = JSONDecoder()

    @concurrent
    static func makeDefault() async throws -> ReadingHistoryPersistence {
        let schema = Schema([StoredReadingProgress.self])
        return try ReadingHistoryPersistence(
            modelContainer: SwiftDataStoreContainer.make(
                schema: schema,
                name: "ReadingProgressV2",
                fileName: AppConfiguration.Persistence.readingHistoryStore,
            ),
        )
    }

    /// 漫画快照与最新进度在一次 save 中提交；失败回滚，不清空已有记录。
    func record(_ update: ReadingProgressUpdate) throws {
        let comic = update.comic.identity
        let rawSourceID = comic.sourceID.rawValue
        let rawComicID = comic.comicID
        let rawMode = update.contentMode.rawValue
        let coverReferenceData = try JSONEncoder().encode(update.comic.cover)
        let now = Date()

        do {
            var descriptor = FetchDescriptor<StoredReadingProgress>(
                predicate: #Predicate {
                    $0.sourceID == rawSourceID
                        && $0.comicID == rawComicID
                        && $0.contentModeRawValue == rawMode
                },
            )
            descriptor.fetchLimit = 1
            if let stored = try modelContext.fetch(descriptor).first {
                stored.title = update.comic.title
                stored.authors = update.comic.authors
                stored.coverReferenceData = coverReferenceData
                stored.chapterID = update.pageIdentity.chapter.chapterID
                stored.pageID = update.pageIdentity.pageID
                stored.pageIndex = update.pageIndex
                stored.chapterTitle = update.chapterTitle
                stored.updatedAt = now
            } else {
                modelContext.insert(StoredReadingProgress(
                    update: update,
                    coverReferenceData: coverReferenceData,
                    updatedAt: now,
                ))
            }
            try modelContext.save()
            revision &+= 1
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    /// 详情页只读取当前作品与内容模式的位置，不解码历史卡片使用的封面快照。
    ///
    /// 存储行缺少章节／页面身份时按没有进度处理，不把损坏记录当成可继续阅读的位置。
    func progress(for identity: ReadingProgressIdentity) throws -> ReadingProgress? {
        let rawSourceID = identity.comic.sourceID.rawValue
        let rawComicID = identity.comic.comicID
        let rawMode = identity.contentMode.rawValue
        var descriptor = FetchDescriptor<StoredReadingProgress>(
            predicate: #Predicate {
                $0.sourceID == rawSourceID
                    && $0.comicID == rawComicID
                    && $0.contentModeRawValue == rawMode
            },
        )
        descriptor.fetchLimit = 1
        guard let stored = try modelContext.fetch(descriptor).first,
              !stored.chapterID.isEmpty,
              !stored.pageID.isEmpty,
              stored.pageIndex >= 0
        else { return nil }

        return ReadingProgress(
            pageIdentity: PageIdentity(
                chapter: ChapterIdentity(comic: identity.comic, chapterID: stored.chapterID),
                pageID: stored.pageID,
            ),
            pageIndex: stored.pageIndex,
            chapterTitle: stored.chapterTitle,
            contentMode: identity.contentMode,
            updatedAt: stored.updatedAt,
        )
    }

    /// 只查询在线记录并按最近阅读时间倒序分页；写入后旧游标失效，页面须从第一页刷新。
    func page(after cursor: ReadingHistoryCursor?) throws -> ReadingHistoryPage {
        if let cursor, cursor.revision != revision {
            throw ReadingHistoryError.historyChanged
        }

        let sortBy = [
            SortDescriptor(\StoredReadingProgress.updatedAt, order: .reverse),
            SortDescriptor(\StoredReadingProgress.sourceID, order: .reverse),
            SortDescriptor(\StoredReadingProgress.comicID, order: .reverse),
        ]
        let onlineMode = ComicContentMode.online.rawValue
        var descriptor: FetchDescriptor<StoredReadingProgress>
        if let cursor {
            let updatedAt = cursor.updatedAt
            let sourceID = cursor.sourceID
            let comicID = cursor.comicID
            descriptor = FetchDescriptor(
                predicate: #Predicate { item in
                    item.contentModeRawValue == onlineMode
                        && (item.updatedAt < updatedAt
                            || (item.updatedAt == updatedAt
                                && (item.sourceID < sourceID
                                    || (item.sourceID == sourceID && item.comicID < comicID))))
                },
                sortBy: sortBy,
            )
        } else {
            descriptor = FetchDescriptor(
                predicate: #Predicate { $0.contentModeRawValue == onlineMode },
                sortBy: sortBy,
            )
        }
        descriptor.fetchLimit = Self.pageSize + 1

        let fetched = try modelContext.fetch(descriptor)
        let rows = Array(fetched.prefix(Self.pageSize))
        // 单项无法读取时跳过该行，不作废整页可用数据；游标仍取原始行，丢弃损坏行不会漏页。
        var unreadableCount = 0
        let items: [ReadingHistoryItem] = rows.compactMap { row in
            do {
                return try makeItem(row)
            } catch {
                unreadableCount += 1
                return nil
            }
        }
        if unreadableCount > 0 {
            AppLogger.warning(
                "阅读记录存在无法读取的行，已跳过，count=\(unreadableCount)",
                category: "Library.History",
            )
        }
        let nextCursor = fetched.count > Self.pageSize ? rows.last.map {
            ReadingHistoryCursor(
                revision: revision,
                updatedAt: $0.updatedAt,
                sourceID: $0.sourceID,
                comicID: $0.comicID,
            )
        } : nil
        return ReadingHistoryPage(items: items, nextCursor: nextCursor)
    }

    /// 删除全部历史；批量删除不发出 `didSave`，提交后显式广播一次让书架重读。
    ///
    /// 逐条删除 5000 行约 0.75 s（2026-11-21 探针），批删是两条语句。
    /// 删除成功同样推进 revision，让在途分页游标失效。
    func deleteAll() throws {
        let count = try modelContext.fetchCount(FetchDescriptor<StoredReadingProgress>())
        guard count > 0 else { return }

        try modelContext.delete(model: StoredReadingProgress.self)
        try modelContext.save()
        revision &+= 1
        PersistentChangeSignal.postBatchChange(entityName: PersistentChangeSignal.Entity.readingProgress)
    }

    /// 删除一个作品的全部阅读记录（在线与离线进度一并删除）。
    ///
    /// 只涉及 1–2 行，保留逐条删除：`didSave` 会照常发出，书架无需显式通知。
    /// 单项删除不推进 revision：删除只会让行消失、不改变其余行的排序位置，键集分页游标
    /// 仍然有效；保持 revision 不变，已加载窗口可以继续续载，删除后不会触发整页重置。
    func delete(comic: ComicIdentity) throws {
        let sourceID = comic.sourceID.rawValue
        let comicID = comic.comicID
        let records = try modelContext.fetch(
            FetchDescriptor<StoredReadingProgress>(
                predicate: #Predicate { $0.sourceID == sourceID && $0.comicID == comicID },
            ),
        )
        guard !records.isEmpty else { return }

        for record in records {
            modelContext.delete(record)
        }
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    /// 统计无法读取的历史记录行（与分页跳过规则共用 `makeItem` 判定）。
    func unreadableRecordCount() throws -> Int {
        try modelContext.fetch(FetchDescriptor<StoredReadingProgress>())
            .count { isUnreadable($0) }
    }

    /// 删除无法读取的历史记录行；删除成功推进 revision，让在途分页游标失效。
    func removeUnreadableRecords() throws -> Int {
        let records = try modelContext.fetch(FetchDescriptor<StoredReadingProgress>())
            .filter { isUnreadable($0) }
        guard !records.isEmpty else { return 0 }

        for record in records {
            modelContext.delete(record)
        }
        do {
            try modelContext.save()
            revision &+= 1
        } catch {
            modelContext.rollback()
            throw error
        }
        return records.count
    }

    /// 行是否无法读取；用 `makeItem` 的实际判定，避免统计与分页跳过两套规则漂移。
    private func isUnreadable(_ stored: StoredReadingProgress) -> Bool {
        do {
            _ = try makeItem(stored)
            return false
        } catch {
            return true
        }
    }

    /// 删除更新时间早于截止点的历史；删除成功同样推进 revision，让在途分页游标失效。
    func prune(olderThan cutoff: Date) throws {
        let descriptor = FetchDescriptor<StoredReadingProgress>(
            predicate: #Predicate { $0.updatedAt < cutoff },
        )
        let expired = try modelContext.fetch(descriptor)
        guard !expired.isEmpty else { return }

        for record in expired {
            modelContext.delete(record)
        }
        try modelContext.save()
        revision &+= 1
    }

    private func makeItem(_ stored: StoredReadingProgress) throws -> ReadingHistoryItem {
        guard let sourceID = ComicSourceID(rawValue: stored.sourceID),
              let contentMode = ComicContentMode(rawValue: stored.contentModeRawValue),
              !stored.comicID.isEmpty,
              !stored.chapterID.isEmpty,
              !stored.pageID.isEmpty,
              stored.pageIndex >= 0
        else {
            throw ReadingHistoryError.invalidStoredRecord
        }

        let comicIdentity = ComicIdentity(sourceID: sourceID, comicID: stored.comicID)
        let cover = try jsonDecoder.decode(ComicImageSource.self, from: stored.coverReferenceData)
        let comic = LibraryComicSnapshot(
            identity: comicIdentity,
            title: stored.title,
            authors: stored.authors,
            cover: cover,
        )
        let chapter = ChapterIdentity(comic: comicIdentity, chapterID: stored.chapterID)
        let page = PageIdentity(chapter: chapter, pageID: stored.pageID)
        return ReadingHistoryItem(
            comic: comic,
            progress: ReadingProgress(
                pageIdentity: page,
                pageIndex: stored.pageIndex,
                chapterTitle: stored.chapterTitle,
                contentMode: contentMode,
                updatedAt: stored.updatedAt,
            ),
        )
    }
}

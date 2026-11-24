import Foundation
import SwiftData

/// 在独立 SwiftData executor 上读写「分类／标签」书签；只向上层返回公共值。
///
/// 关注的作者不在这里：那是另一个库、另一套读写（见 `FollowingPersistence`）。
/// 这里保存的 `kindID` 只会是分类、标签或来源自定义的检索维度，不处理作者。
@ModelActor
actor BookmarkPersistence {
    @concurrent
    static func makeDefault() async throws -> BookmarkPersistence {
        let schema = Schema([StoredBookmark.self])
        return try BookmarkPersistence(
            modelContainer: SwiftDataStoreContainer.make(
                schema: schema,
                name: "BookmarkV3",
                fileName: AppConfiguration.Persistence.bookmarkStore,
            ),
        )
    }

    /// 保存一条书签；已收藏时刷新 payload 与收藏时间（书架按时间倒序，跳转用最新身份）。
    func save(_ bookmark: Bookmark) throws {
        let now = Date()
        if let stored = try record(for: bookmark) {
            stored.payload = bookmark.payload
            stored.savedAt = now
        } else {
            modelContext.insert(StoredBookmark(bookmark: bookmark, savedAt: now))
        }

        try modelContext.save()
    }

    /// 全部收藏，最近收藏在前；来源已不存在的行跳过，不影响其余内容。
    ///
    /// 不分批：书签量级有限，一次取完交给 `LazyVStack` 只构建可见胶囊，
    /// 比维护游标、跨页写入与续载失败简单得多。
    func entries() throws -> [Bookmark] {
        let rows = try modelContext.fetch(
            FetchDescriptor<StoredBookmark>(
                sortBy: [
                    SortDescriptor(\.savedAt, order: .reverse),
                    // 同一时刻收藏的两条按「来源 + 展示名」定序，避免每次读取顺序抖动。
                    SortDescriptor(\.sourceID, order: .reverse),
                    SortDescriptor(\.displayName, order: .reverse),
                ],
            ),
        )
        let bookmarks = rows.compactMap(\.bookmark)

        if bookmarks.count != rows.count {
            AppLogger.warning(
                "书签收藏存在无法读取的行，已跳过，count=\(rows.count - bookmarks.count)",
                category: "Bookmarks",
            )
        }

        return bookmarks
    }

    /// 该书签是否已收藏。
    func contains(_ bookmark: Bookmark) throws -> Bool {
        try record(for: bookmark) != nil
    }

    /// 取消收藏；没有这一行时是空操作。
    ///
    /// 单行删除走对象删除而不是批删：批删不发 `didSave`，书架「书签」页靠它保持跨页一致；
    /// 一行数据也没有批删的收益。
    func remove(_ bookmark: Bookmark) throws {
        guard let stored = try record(for: bookmark) else {
            return
        }

        modelContext.delete(stored)
        try modelContext.save()
    }

    /// 删除某个维度（分类或标签）的全部收藏，跨来源。
    func removeAll(kindID: String) throws {
        try modelContext.delete(
            model: StoredBookmark.self,
            where: #Predicate { $0.kind == kindID },
        )
        try modelContext.save()
        PersistentChangeSignal.postBatchChange(entityName: PersistentChangeSignal.Entity.bookmark)
    }

    /// 按「来源 + 维度 + 展示名」查一行（`#Unique` 唯一索引）。
    private func record(for bookmark: Bookmark) throws -> StoredBookmark? {
        let raw = bookmark.sourceID.rawValue
        let kind = bookmark.kindID
        let name = bookmark.displayName
        var descriptor = FetchDescriptor<StoredBookmark>(
            predicate: #Predicate { $0.sourceID == raw && $0.kind == kind && $0.displayName == name },
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }
}

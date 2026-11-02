import Foundation
import SwiftData

/// 在独立 SwiftData executor 上读写书签收藏；只向上层返回公共值。
@ModelActor
actor BookmarkPersistence {
    @concurrent
    static func makeDefault() async throws -> BookmarkPersistence {
        let schema = Schema([StoredBookmark.self])
        return try BookmarkPersistence(
            modelContainer: SwiftDataStoreContainer.make(
                schema: schema,
                name: "BookmarkV1",
                fileName: AppConfiguration.Persistence.bookmarkStore,
            ),
        )
    }

    /// 保存一条收藏；已收藏时刷新 payload 与收藏时间（书架按时间倒序，跳转用最新身份）。
    func save(_ bookmark: Bookmark, now: Date) throws {
        if let stored = try record(for: bookmark) {
            stored.payload = bookmark.payload
            stored.savedAt = now
        } else {
            modelContext.insert(StoredBookmark(bookmark: bookmark, savedAt: now))
        }

        try modelContext.save()
    }

    /// 全部收藏，最近收藏在前；单行来源或维度失效时跳过该行，不影响其余内容。
    func entries() throws -> [Bookmark] {
        let rows = try modelContext.fetch(
            FetchDescriptor<StoredBookmark>(
                sortBy: [SortDescriptor(\.savedAt, order: .reverse)],
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

    /// 取消收藏。
    func remove(_ bookmark: Bookmark) throws {
        guard let stored = try record(for: bookmark) else {
            return
        }

        modelContext.delete(stored)
        try modelContext.save()
    }

    /// 删除某个维度的全部收藏（书架分组右侧的「清除」）。
    func removeAll(kind: BookmarkKind) throws {
        let rawKind = kind.rawValue
        try modelContext.delete(
            model: StoredBookmark.self,
            where: #Predicate { $0.kind == rawKind },
        )
        try modelContext.save()
    }

    /// 按身份键查一行。
    private func record(for bookmark: Bookmark) throws -> StoredBookmark? {
        let key = bookmark.identityKey
        var descriptor = FetchDescriptor<StoredBookmark>(
            predicate: #Predicate { $0.identityKey == key },
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }
}

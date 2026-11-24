import Foundation
import SwiftData

/// 搜索历史两个分区的权威快照。
///
/// 同一次读取得到，避免分两次查询时被写入拆开；`queries` 与 `favorites` 互斥，同一条词只会出现在一处。
struct SearchHistorySnapshot: Sendable {
    let queries: [String]
    let favorites: [String]
}

/// 在独立 SwiftData executor 上按来源处理搜索历史；只向上层返回关键词字符串。
///
/// 收藏是历史行上的 `favoritedAt` 标记：两个分区读同一张表、按标记分流，
/// 因此同一条词不可能同时出现在「收藏的搜索词」和「最近搜索」。
@ModelActor
actor SearchHistoryPersistence {
    /// 未收藏项的每来源保留上限；超过的按最近裁剪，收藏项不参与。
    private static let entriesPerSource = AppConfiguration.SearchHistory.maxEntriesPerSource

    @concurrent
    static func makeDefault() async throws -> SearchHistoryPersistence {
        let schema = Schema([StoredSearchHistory.self])
        return try SearchHistoryPersistence(
            modelContainer: SwiftDataStoreContainer.make(
                schema: schema,
                name: "SearchHistoryV3",
                fileName: AppConfiguration.Persistence.searchHistoryStore,
            ),
        )
    }

    /// 两个分区的权威快照：一次读取同一份行数据，再在内存里分流、排序与裁剪。
    func snapshot(for sourceID: ComicSourceID) throws -> SearchHistorySnapshot {
        let rows = try rows(for: sourceID)

        let queries = rows
            .filter { $0.favoritedAt == nil }
            .sorted { lhs, rhs in
                if lhs.searchedAt != rhs.searchedAt {
                    return lhs.searchedAt > rhs.searchedAt
                }
                return lhs.query < rhs.query
            }
            .prefix(Self.entriesPerSource)
            .map(\.query)

        let favorites = rows
            .compactMap { row in row.favoritedAt.map { (query: row.query, at: $0) } }
            .sorted { lhs, rhs in
                if lhs.at != rhs.at {
                    return lhs.at < rhs.at
                }
                return lhs.query < rhs.query
            }
            .map(\.query)

        return SearchHistorySnapshot(queries: queries, favorites: favorites)
    }

    /// 记录一次搜索：按关键词去重（存在则更新最近时间，保留收藏标记），并把该来源未收藏项裁剪到上限。
    ///
    /// 去重靠 `#Unique(sourceID, query)` 兜底；这里仍显式查一次，是为了区分「新增」与「更新」：
    /// 只有新增才需要裁剪，重复搜索不动条数。
    func record(sourceID: ComicSourceID, query: String) throws -> SearchHistorySnapshot {
        let raw = sourceID.rawValue
        let now = Date()
        var descriptor = FetchDescriptor<StoredSearchHistory>(
            predicate: #Predicate { $0.sourceID == raw && $0.query == query },
        )
        descriptor.fetchLimit = 1

        if let stored = try modelContext.fetch(descriptor).first {
            stored.searchedAt = now
            try modelContext.save()
        } else {
            modelContext.insert(StoredSearchHistory(sourceID: sourceID, query: query, searchedAt: now))
            try modelContext.save()
            try prune(sourceID: sourceID)
        }

        return try snapshot(for: sourceID)
    }

    /// 收藏或取消收藏；收藏时间取当前时刻，决定收藏区里的先后。
    ///
    /// 已收藏时重复收藏不刷新收藏时间，避免重复动作改变收藏区顺序。
    /// 取消收藏只清标记，`searchedAt` 不动——回到「最近搜索」时按它排位（收藏期间再次搜索会刷新该时间）。
    func setFavorited(
        _ favorited: Bool,
        sourceID: ComicSourceID,
        query: String,
    ) throws -> SearchHistorySnapshot {
        let raw = sourceID.rawValue
        var descriptor = FetchDescriptor<StoredSearchHistory>(
            predicate: #Predicate { $0.sourceID == raw && $0.query == query },
        )
        descriptor.fetchLimit = 1
        guard let stored = try modelContext.fetch(descriptor).first else {
            return try snapshot(for: sourceID)
        }

        if favorited {
            if stored.favoritedAt == nil {
                stored.favoritedAt = Date()
            }
        } else {
            stored.favoritedAt = nil
        }
        try modelContext.save()

        return try snapshot(for: sourceID)
    }

    /// 删除某来源的一条关键词历史。
    func remove(sourceID: ComicSourceID, query: String) throws -> SearchHistorySnapshot {
        let raw = sourceID.rawValue
        try modelContext.delete(
            model: StoredSearchHistory.self,
            where: #Predicate { $0.sourceID == raw && $0.query == query },
        )
        try modelContext.save()

        return try snapshot(for: sourceID)
    }

    /// 清空某来源的收藏：删除收藏记录本身，词不会回到「最近搜索」。
    ///
    /// 与单条 `setFavorited(false)` 不同：那是取消收藏，只清标记、按 `searchedAt` 归位。
    func clearFavorites(sourceID: ComicSourceID) throws -> SearchHistorySnapshot {
        for row in try rows(for: sourceID) where row.favoritedAt != nil {
            modelContext.delete(row)
        }
        try modelContext.save()

        return try snapshot(for: sourceID)
    }

    /// 清除某来源的「最近搜索」；收藏的搜索词保留。
    func clear(sourceID: ComicSourceID) throws -> SearchHistorySnapshot {
        for row in try rows(for: sourceID) where row.favoritedAt == nil {
            modelContext.delete(row)
        }
        try modelContext.save()

        return try snapshot(for: sourceID)
    }

    /// 只保留某来源最近的 `limit` 条未收藏记录，收藏项始终保留。
    private func prune(sourceID: ComicSourceID) throws {
        let unpinned = try rows(for: sourceID)
            .filter { $0.favoritedAt == nil }
            .sorted { $0.searchedAt > $1.searchedAt }
        guard unpinned.count > Self.entriesPerSource else { return }

        for row in unpinned.dropFirst(Self.entriesPerSource) {
            modelContext.delete(row)
        }
        try modelContext.save()
    }

    /// 某来源的全部行（未收藏 + 收藏）；行数很小，分区在内存里分流。
    private func rows(for sourceID: ComicSourceID) throws -> [StoredSearchHistory] {
        let raw = sourceID.rawValue
        return try modelContext.fetch(
            FetchDescriptor<StoredSearchHistory>(predicate: #Predicate { $0.sourceID == raw }),
        )
    }
}

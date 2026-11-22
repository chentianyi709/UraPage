import Foundation
import SwiftData

/// 在独立 SwiftData executor 上按来源处理搜索历史；只向上层返回关键词字符串。
@ModelActor
actor SearchHistoryPersistence {
    /// 每来源保留上限；超过的按最近裁剪。
    private static let entriesPerSource = AppConfiguration.SearchHistory.maxEntriesPerSource

    @concurrent
    static func makeDefault() async throws -> SearchHistoryPersistence {
        let schema = Schema([StoredSearchHistory.self])
        return try SearchHistoryPersistence(
            modelContainer: SwiftDataStoreContainer.make(
                schema: schema,
                name: "SearchHistoryV2",
                fileName: AppConfiguration.Persistence.searchHistoryStore,
            ),
        )
    }

    /// 记录一次搜索：按关键词去重（存在则更新最近时间），并把该来源裁剪到上限。
    ///
    /// 去重靠 `#Unique(sourceID, query)` 兜底；这里仍显式查一次，是为了区分「新增」与「置顶」：
    /// 只有新增才需要裁剪，重复搜索不动条数。
    func record(sourceID: ComicSourceID, query: String) throws {
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
    }

    /// 某来源的历史关键词，最近在前。
    func queries(for sourceID: ComicSourceID) throws -> [String] {
        let raw = sourceID.rawValue
        var descriptor = FetchDescriptor<StoredSearchHistory>(
            predicate: #Predicate { $0.sourceID == raw },
            sortBy: [SortDescriptor(\.searchedAt, order: .reverse)],
        )
        descriptor.fetchLimit = Self.entriesPerSource

        return try modelContext.fetch(descriptor).map(\.query)
    }

    /// 删除某来源的一条关键词历史。
    func remove(sourceID: ComicSourceID, query: String) throws {
        let raw = sourceID.rawValue
        try modelContext.delete(
            model: StoredSearchHistory.self,
            where: #Predicate { $0.sourceID == raw && $0.query == query },
        )
        try modelContext.save()
    }

    /// 清空某来源的全部搜索历史。
    func clear(sourceID: ComicSourceID) throws {
        let raw = sourceID.rawValue
        try modelContext.delete(
            model: StoredSearchHistory.self,
            where: #Predicate { $0.sourceID == raw },
        )
        try modelContext.save()
    }

    /// 只保留某来源最近的 `limit` 条，其余删除。
    private func prune(sourceID: ComicSourceID) throws {
        let raw = sourceID.rawValue
        let descriptor = FetchDescriptor<StoredSearchHistory>(
            predicate: #Predicate { $0.sourceID == raw },
            sortBy: [SortDescriptor(\.searchedAt, order: .reverse)],
        )
        let records = try modelContext.fetch(descriptor)
        let limit = Self.entriesPerSource
        guard records.count > limit else { return }

        for record in records.dropFirst(limit) {
            modelContext.delete(record)
        }
        try modelContext.save()
    }
}

import Foundation
import SwiftData

/// 在独立 SwiftData executor 上按来源处理搜索历史；只向上层返回关键词字符串。
@ModelActor
actor SearchHistoryPersistence {
    @concurrent
    static func makeDefault() async throws -> SearchHistoryPersistence {
        let schema = Schema([StoredSearchHistory.self])
        return try SearchHistoryPersistence(
            modelContainer: SwiftDataStoreContainer.make(
                schema: schema,
                name: "SearchHistoryV1",
                fileName: AppConfiguration.Persistence.searchHistoryStore,
            ),
        )
    }

    /// 记录一次搜索：按关键词去重（存在则更新最近时间），并把该来源裁剪到上限。
    func record(sourceID: ComicSourceID, query: String, limit: Int, now: Date) throws {
        let key = StoredSearchHistory.key(sourceID: sourceID, query: query)
        var descriptor = FetchDescriptor<StoredSearchHistory>(
            predicate: #Predicate { $0.identityKey == key },
        )
        descriptor.fetchLimit = 1

        if let stored = try modelContext.fetch(descriptor).first {
            // 已存在的关键词只更新时间，数量不变，无需裁剪。
            stored.searchedAt = now
            try modelContext.save()
        } else {
            modelContext.insert(StoredSearchHistory(sourceID: sourceID, query: query, searchedAt: now))
            try modelContext.save()
            try prune(sourceID: sourceID, limit: limit)
        }
    }

    /// 某来源的历史关键词，最近在前。
    func queries(for sourceID: ComicSourceID, limit: Int) throws -> [String] {
        let raw = sourceID.rawValue
        var descriptor = FetchDescriptor<StoredSearchHistory>(
            predicate: #Predicate { $0.sourceID == raw },
            sortBy: [SortDescriptor(\.searchedAt, order: .reverse)],
        )
        descriptor.fetchLimit = limit

        return try modelContext.fetch(descriptor).map(\.query)
    }

    /// 删除某来源的一条关键词历史。
    func remove(sourceID: ComicSourceID, query: String) throws {
        let key = StoredSearchHistory.key(sourceID: sourceID, query: query)
        let records = try modelContext.fetch(
            FetchDescriptor<StoredSearchHistory>(predicate: #Predicate { $0.identityKey == key }),
        )
        guard !records.isEmpty else { return }

        for record in records {
            modelContext.delete(record)
        }
        try modelContext.save()
    }

    /// 清空某来源的全部搜索历史。
    func clear(sourceID: ComicSourceID) throws {
        let raw = sourceID.rawValue
        let records = try modelContext.fetch(
            FetchDescriptor<StoredSearchHistory>(predicate: #Predicate { $0.sourceID == raw }),
        )
        guard !records.isEmpty else { return }

        for record in records {
            modelContext.delete(record)
        }
        try modelContext.save()
    }

    /// 只保留某来源最近的 `limit` 条，其余删除。
    private func prune(sourceID: ComicSourceID, limit: Int) throws {
        let raw = sourceID.rawValue
        let descriptor = FetchDescriptor<StoredSearchHistory>(
            predicate: #Predicate { $0.sourceID == raw },
            sortBy: [SortDescriptor(\.searchedAt, order: .reverse)],
        )
        let records = try modelContext.fetch(descriptor)
        guard records.count > limit else { return }

        for record in records.dropFirst(limit) {
            modelContext.delete(record)
        }
        try modelContext.save()
    }
}

import Foundation

/// 搜索历史的进程级唯一入口：按来源隔离，持久化在独立 SwiftData executor 上。
actor SearchHistoryStore {
    private var persistenceTask: Task<SearchHistoryPersistence, any Error>?

    /// 记录一次搜索；空关键词忽略。
    func record(sourceID: ComicSourceID, query: String) async throws {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        try await persistence().record(
            sourceID: sourceID,
            query: trimmed,
            limit: AppConfiguration.SearchHistory.maxEntriesPerSource,
            now: Date(),
        )
    }

    /// 某来源的历史关键词，最近在前。
    func queries(for sourceID: ComicSourceID) async throws -> [String] {
        try await persistence().queries(
            for: sourceID,
            limit: AppConfiguration.SearchHistory.maxEntriesPerSource,
        )
    }

    /// 删除某来源的一条关键词历史。
    func remove(sourceID: ComicSourceID, query: String) async throws {
        try await persistence().remove(sourceID: sourceID, query: query)
    }

    /// 清空某来源的全部搜索历史。
    func clear(sourceID: ComicSourceID) async throws {
        try await persistence().clear(sourceID: sourceID)
    }

    private func persistence() async throws -> SearchHistoryPersistence {
        if let persistenceTask {
            return try await persistenceTask.value
        }
        let task = Task {
            try await SearchHistoryPersistence.makeDefault()
        }
        persistenceTask = task
        do {
            return try await task.value
        } catch {
            persistenceTask = nil
            throw error
        }
    }
}

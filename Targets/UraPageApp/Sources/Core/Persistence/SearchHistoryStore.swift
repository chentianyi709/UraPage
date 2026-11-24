import Foundation

/// 搜索历史的进程级唯一入口：按来源隔离，持久化在独立 SwiftData executor 上。
actor SearchHistoryStore {
    private var persistenceTask: Task<SearchHistoryPersistence, any Error>?

    /// 两个分区的权威快照：一次读取得到，避免两个分区来自不同时间点。
    func snapshot(for sourceID: ComicSourceID) async throws -> SearchHistorySnapshot {
        try await persistence().snapshot(for: sourceID)
    }

    /// 记录一次搜索并返回更新后的快照；关键词的整理与空值判断由调用方（`SearchHistoryViewModel`）负责。
    func record(sourceID: ComicSourceID, query: String) async throws -> SearchHistorySnapshot {
        try await persistence().record(sourceID: sourceID, query: query)
    }

    /// 收藏或取消收藏，并返回更新后的快照。
    func setFavorited(
        _ favorited: Bool,
        sourceID: ComicSourceID,
        query: String,
    ) async throws -> SearchHistorySnapshot {
        try await persistence().setFavorited(favorited, sourceID: sourceID, query: query)
    }

    /// 清空某来源的收藏（删除这些收藏词），并返回更新后的快照。
    func clearFavorites(for sourceID: ComicSourceID) async throws -> SearchHistorySnapshot {
        try await persistence().clearFavorites(sourceID: sourceID)
    }

    /// 删除某来源的一条关键词历史，并返回更新后的快照。
    func remove(sourceID: ComicSourceID, query: String) async throws -> SearchHistorySnapshot {
        try await persistence().remove(sourceID: sourceID, query: query)
    }

    /// 清除某来源的「最近搜索」；收藏的搜索词保留；返回更新后的快照。
    func clear(sourceID: ComicSourceID) async throws -> SearchHistorySnapshot {
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

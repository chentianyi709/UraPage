import Foundation

/// 分类／标签书签的进程级唯一入口：独立 SwiftData executor，首次使用时懒加载。
///
/// 关注作者走 `FollowingStore`：两个库、两套读写，互不影响。
actor BookmarkStore {
    private var persistenceTask: Task<BookmarkPersistence, any Error>?

    /// 收藏一条书签；重复收藏时刷新 payload 与收藏时间。
    func save(_ bookmark: Bookmark) async throws {
        try await persistence().save(bookmark)
    }

    /// 全部收藏，最近收藏在前。
    func entries() async throws -> [Bookmark] {
        try await persistence().entries()
    }

    /// 该书签是否已收藏。
    func isFavorite(_ bookmark: Bookmark) async throws -> Bool {
        try await persistence().contains(bookmark)
    }

    /// 取消收藏。
    func remove(_ bookmark: Bookmark) async throws {
        try await persistence().remove(bookmark)
    }

    /// 删除某个维度（分类或标签）的全部收藏，跨来源。
    func removeAll(kindID: String) async throws {
        try await persistence().removeAll(kindID: kindID)
    }

    private func persistence() async throws -> BookmarkPersistence {
        if let persistenceTask {
            return try await persistenceTask.value
        }
        let task = Task {
            try await BookmarkPersistence.makeDefault()
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

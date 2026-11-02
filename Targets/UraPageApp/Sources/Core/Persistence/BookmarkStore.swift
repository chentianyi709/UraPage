import Foundation

/// 书签收藏的进程级唯一入口：独立 SwiftData executor，首次使用时懒加载。
actor BookmarkStore {
    private var persistenceTask: Task<BookmarkPersistence, any Error>?

    /// 收藏一条书签；重复收藏时刷新 payload 与收藏时间。
    func save(_ bookmark: Bookmark) async throws {
        try await persistence().save(bookmark, now: Date())
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

    /// 删除某个维度的全部收藏。
    func removeAll(kind: BookmarkKind) async throws {
        try await persistence().removeAll(kind: kind)
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

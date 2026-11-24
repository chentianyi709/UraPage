import Foundation

/// 关注作者的进程级唯一入口：独立 SwiftData 库，首次使用时懒加载。
///
/// 与 `BookmarkStore` 分开：关注的读写不经过书签的 store，
/// 两边的失败、装配与迁移都互不影响。
actor FollowingStore {
    private var persistenceTask: Task<FollowingPersistence, any Error>?

    /// 关注一位作者；重复关注时刷新 payload 与关注时间。
    func save(_ following: Following) async throws {
        try await persistence().save(following)
    }

    /// 全部关注，最近关注在前。
    func entries() async throws -> [Following] {
        try await persistence().entries()
    }

    /// 该作者是否已关注。
    func contains(_ following: Following) async throws -> Bool {
        try await persistence().contains(following)
    }

    /// 取消关注。
    func remove(_ following: Following) async throws {
        try await persistence().remove(following)
    }

    /// 清空全部关注。
    func removeAll() async throws {
        try await persistence().removeAll()
    }

    private func persistence() async throws -> FollowingPersistence {
        if let persistenceTask {
            return try await persistenceTask.value
        }
        let task = Task {
            try await FollowingPersistence.makeDefault()
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

import Foundation
import SwiftData

/// 在独立 SwiftData executor 上读写关注的作者；只向上层返回公共值。
///
/// 与书签分库分表：这里只认 `Following`，读写路径不认识 `Bookmark`，
/// 两边的增删互不影响，也不需要在入口处按维度分流。
@ModelActor
actor FollowingPersistence {
    @concurrent
    static func makeDefault() async throws -> FollowingPersistence {
        let schema = Schema([StoredFollowing.self])
        return try FollowingPersistence(
            modelContainer: SwiftDataStoreContainer.make(
                schema: schema,
                name: "FollowingsV1",
                fileName: AppConfiguration.Persistence.followingStore,
            ),
        )
    }

    /// 保存一条关注；已关注时刷新 payload 与关注时间（最近关注排在前面）。
    func save(_ following: Following) throws {
        let now = Date()
        if let stored = try record(for: following) {
            stored.payload = following.payload
            stored.followedAt = now
        } else {
            modelContext.insert(StoredFollowing(following: following, followedAt: now))
        }

        try modelContext.save()
    }

    /// 全部关注，最近关注在前；来源已不存在的行跳过。
    func entries() throws -> [Following] {
        let rows = try modelContext.fetch(
            FetchDescriptor<StoredFollowing>(
                sortBy: [
                    SortDescriptor(\.followedAt, order: .reverse),
                    // 同一时刻关注的两条按「来源 + 作者名」定序，避免顺序抖动。
                    SortDescriptor(\.sourceID, order: .reverse),
                    SortDescriptor(\.name, order: .reverse),
                ],
            ),
        )
        let followings = rows.compactMap(\.following)

        if followings.count != rows.count {
            AppLogger.warning(
                "关注存在无法读取的行，已跳过，count=\(rows.count - followings.count)",
                category: "Followings",
            )
        }

        return followings
    }

    /// 该作者是否已关注。
    func contains(_ following: Following) throws -> Bool {
        try record(for: following) != nil
    }

    /// 取消关注；没有这一行时是空操作。
    ///
    /// 单行删除走对象删除而不是批删：批删不发 `didSave`，书签页靠它保持跨页一致；
    /// 一行数据也没有批删的收益。
    func remove(_ following: Following) throws {
        guard let stored = try record(for: following) else {
            return
        }

        modelContext.delete(stored)
        try modelContext.save()
    }

    /// 清空全部关注。
    func removeAll() throws {
        try modelContext.delete(model: StoredFollowing.self, where: #Predicate { _ in true })
        try modelContext.save()
        PersistentChangeSignal.postBatchChange(entityName: PersistentChangeSignal.Entity.following)
    }

    /// 按「来源 + 作者名」查一行（`#Unique` 唯一索引）。
    private func record(for following: Following) throws -> StoredFollowing? {
        let raw = following.sourceID.rawValue
        let name = following.name
        var descriptor = FetchDescriptor<StoredFollowing>(
            predicate: #Predicate { $0.sourceID == raw && $0.name == name },
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }
}

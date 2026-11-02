import Foundation

/// 阅读进度、跨来源历史查询与过期清理的进程级唯一入口。
actor ReadingHistoryStore {
    private var persistenceTask: Task<ReadingHistoryPersistence, any Error>?

    /// 当前保留天数；`nil` 表示不限制。由通用设置 owner 在启动与修改时写入。
    private var retentionDays: Int? = ReadingHistoryRetention.defaultValue.dayCount

    /// 由阅读历史设置 owner 推入当前保留档位。
    func setRetentionDays(_ days: Int?) {
        retentionDays = days
    }

    func record(_ update: ReadingProgressUpdate) async throws {
        guard update.comic.identity == update.pageIdentity.chapter.comic,
              !update.pageIdentity.pageID.isEmpty,
              update.pageIndex >= 0
        else {
            throw ReadingHistoryError.invalidUpdate
        }

        try await persistence().record(update)
    }

    /// 纯读取，不触发清理；过期清理由启动、修改档位与历史页刷新显式触发。
    func page(after cursor: ReadingHistoryCursor?) async throws -> ReadingHistoryPage {
        try await persistence().page(after: cursor)
    }

    func progress(for identity: ReadingProgressIdentity) async throws -> ReadingProgress? {
        try await persistence().progress(for: identity)
    }

    /// 删除全部阅读历史（含继续阅读进度）。
    func deleteAll() async throws {
        try await persistence().deleteAll()
    }

    /// 删除一个作品的阅读记录（在线与离线进度一并删除）。
    func delete(comic: ComicIdentity) async throws {
        try await persistence().delete(comic: comic)
    }

    /// 统计无法读取的阅读记录行（设置页「清理其他数据」预览）。
    func unreadableRecordCount() async throws -> Int {
        try await persistence().unreadableRecordCount()
    }

    /// 删除无法读取的阅读记录行；删除成功会让在途分页游标失效。
    func removeUnreadableRecords() async throws -> Int {
        try await persistence().removeUnreadableRecords()
    }

    /// 按当前保留档位删除过期历史；`nil`（不限制）时什么都不做。
    func pruneExpiredIfNeeded() async throws {
        guard let days = retentionDays,
              let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date())
        else {
            return
        }

        try await persistence().prune(olderThan: cutoff)
    }

    private func persistence() async throws -> ReadingHistoryPersistence {
        if let persistenceTask {
            return try await persistenceTask.value
        }
        let task = Task {
            try await ReadingHistoryPersistence.makeDefault()
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

enum ReadingHistoryError: Error {
    case invalidUpdate
    case invalidStoredRecord
    case historyChanged
}

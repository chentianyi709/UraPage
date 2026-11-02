import Foundation
import SwiftData

// MARK: - 封面状态

extension DownloadPersistence {
    /// 读取一个排队中作品的封面传输输入；作品身份或封面引用不可读时返回 `nil`。
    func pendingCoverTransfer(for work: StoredDownloadedComic) throws -> PendingCoverTransfer? {
        guard let identity = work.identity else { return nil }

        let cover = try JSONDecoder().decode(ComicImageSource.self, from: work.coverReferenceData)
        guard case .remote = cover else { return nil }

        return PendingCoverTransfer(identity: identity, cover: cover)
    }

    /// 记录封面文件已写入作品资产目录。
    func saveCoverAsset(
        expectedCover: ComicImageSource,
        for comic: ComicIdentity,
        now: Date,
    ) throws -> Bool {
        do {
            guard let work = try fetchWork(key: StoredDownloadedComic.key(for: comic)) else {
                throw DownloadPersistenceError.missingComicRecord
            }

            let currentCover = try JSONDecoder().decode(ComicImageSource.self, from: work.coverReferenceData)
            guard work.coverState == .downloading,
                  currentCover == expectedCover
            else {
                return false
            }

            work.coverState = .completed
            work.updatedAt = now
            markProjectionDirty(for: comic)
            try saveChanges()
            return true
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    /// 标记封面资产处理开始；缓存查找、缓存复制和网络获取都属于下载阶段。
    @discardableResult
    func startCover(for comic: ComicIdentity, now: Date) throws -> Bool {
        guard let work = try fetchWork(key: StoredDownloadedComic.key(for: comic)),
              work.coverState == .queued
        else { return false }

        work.coverState = .downloading
        work.updatedAt = now
        markProjectionDirty(for: comic)
        try saveChanges()
        return true
    }

    /// Host 切换后把仍在下载的封面退回排队；已完成、失败或暂停的封面保持原状。
    ///
    /// 旧封面任务先取消并等待结束，再调用本方法，避免旧 Host 结果与重开任务交错。
    func requeueDownloadingCover(for comic: ComicIdentity, now: Date) throws {
        guard let work = try fetchWork(key: StoredDownloadedComic.key(for: comic)),
              work.coverState == .downloading
        else { return }

        work.coverState = .queued
        work.updatedAt = now
        markProjectionDirty(for: comic)
        try saveChanges()
    }

    /// 记录封面失败；来源引用或状态已变化时拒绝旧任务结果。
    func failCover(
        for comic: ComicIdentity,
        expectedCover: ComicImageSource,
        now: Date,
    ) throws -> Bool {
        guard let work = try fetchWork(key: StoredDownloadedComic.key(for: comic)),
              work.coverState == .downloading,
              try JSONDecoder().decode(ComicImageSource.self, from: work.coverReferenceData) == expectedCover
        else { return false }

        work.coverState = .failed
        work.updatedAt = now
        markProjectionDirty(for: comic)
        try saveChanges()
        return true
    }
}

private enum DownloadPersistenceError: Error {
    case missingComicRecord
}

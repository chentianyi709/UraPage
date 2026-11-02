import Foundation
import SwiftData

// MARK: - 启动对账与调度状态

extension DownloadPersistence {
    /// 启动对账：把上次被强杀遗留的下载中章节与封面回退为排队，交由启动后重新调度。
    ///
    /// 只处理本 App 自身可能留下的中断状态；不再尝试解释无法识别的持久化值。
    /// 新 App 不考虑旧数据结构兼容，状态值只由本进程按 `DownloadState` 写入。
    func recoverInterrupted() throws {
        let downloading = DownloadState.downloading.rawValue
        var changed = false

        let rows = try modelContext.fetch(
            FetchDescriptor<StoredDownload>(
                predicate: #Predicate { $0.stateRawValue == downloading },
            ),
        )
        for row in rows {
            row.state = .queued
            row.jobID = nil
            markProjectionDirty(workKey: Self.workKey(of: row))
            changed = true
        }

        let works = try modelContext.fetch(
            FetchDescriptor<StoredDownloadedComic>(
                predicate: #Predicate { $0.coverStateRawValue == downloading },
            ),
        )
        for work in works {
            work.coverState = .queued
            markProjectionDirty(workKey: work.identityKey)
            changed = true
        }

        guard changed else { return }

        try saveChanges()
    }

    /// 启动对账后仍需下载的章节身份；中断阶段已先回退为排队状态。
    func pendingChapters() throws -> [ChapterIdentity] {
        let queued = DownloadState.queued.rawValue
        let descriptor = FetchDescriptor<StoredDownload>(
            predicate: #Predicate { $0.stateRawValue == queued },
        )
        return try modelContext.fetch(descriptor).compactMap(\.chapterIdentity)
    }

    /// 挂起作品时同时暂停未完成封面；即使章节都已完成，暂停意图也会留在作品资产记录中。
    func pauseWork(for comic: ComicIdentity, now: Date) throws {
        let rows = try fetchDownloads(for: comic)
        var changed = false
        for row in rows where row.state?.canPause == true {
            row.state = .paused
            row.jobID = nil
            row.stateChangedAt = now
            changed = true
        }

        if let work = try fetchWork(key: StoredDownloadedComic.key(for: comic)),
           work.coverState?.canPause == true {
            work.coverState = .paused
            changed = true
        }
        guard changed else { return }

        markProjectionDirty(for: comic)
        try touchWorks(keys: [StoredDownloadedComic.key(for: comic)], now: now)
        try saveChanges()
    }

    /// 批量暂停作品：一次事务写入全部可暂停的章节与封面，供「清除下载记录」使用。
    ///
    /// 与逐个 `pauseWork` 的语义一致（只暂停 `canPause` 的状态、没有变化不写库），
    /// 但避免活动作品多时每个作品各提交一次 SwiftData 事务。
    func pauseWorks(for comics: [ComicIdentity], now: Date) throws {
        var changedWorkKeys: Set<String> = []
        for comic in comics {
            var changed = false
            for row in try fetchDownloads(for: comic) where row.state?.canPause == true {
                row.state = .paused
                row.jobID = nil
                row.stateChangedAt = now
                changed = true
            }
            if let work = try fetchWork(key: StoredDownloadedComic.key(for: comic)),
               work.coverState?.canPause == true {
                work.coverState = .paused
                changed = true
            }
            if changed {
                changedWorkKeys.insert(StoredDownloadedComic.key(for: comic))
            }
        }
        guard !changedWorkKeys.isEmpty else { return }

        for key in changedWorkKeys {
            markProjectionDirty(workKey: key)
        }
        try touchWorks(keys: changedWorkKeys, now: now)
        try saveChanges()
    }

    /// 开始下载一个章节：仅在仍处于排队态时生效，并绑定 jobID。
    @discardableResult
    func startChapter(_ identity: ChapterIdentity, jobID: UUID, now: Date) throws -> Bool {
        guard let stored = try fetchDownload(key: StoredDownload.key(for: identity)),
              stored.state == .queued
        else {
            return false
        }

        stored.state = .downloading
        stored.jobID = jobID
        stored.stateChangedAt = now
        markProjectionDirty(for: identity.comic)
        try saveChanges()
        return true
    }

    /// 提交章节最终状态；jobID 不匹配（旧任务）时忽略。
    ///
    /// 返回是否实际写入；调用方据此决定是否更新运行时状态，旧运行不能覆盖已被接管或重排的章节。
    @discardableResult
    func finishChapter(
        _ identity: ChapterIdentity,
        jobID: UUID,
        state: DownloadState,
        now: Date,
    ) throws -> Bool {
        guard let stored = try fetchDownload(key: StoredDownload.key(for: identity)),
              stored.state == .downloading,
              stored.jobID == jobID
        else {
            return false
        }

        stored.state = state
        stored.jobID = nil
        stored.stateChangedAt = now
        markProjectionDirty(for: identity.comic)
        try touchWorks(keys: [StoredDownloadedComic.key(for: identity.comic)], now: now)
        try saveChanges()
        return true
    }

    /// Host 切换后把作品所有仍处于「下载中」的章节退回排队。
    ///
    /// 调用方已等待旧 run 完全结束，并用重启屏障阻止新 run 启动；因此这些「下载中」行都属于旧 run，
    /// 也覆盖「启动状态已写入、运行时还没来得及记录下载中章节」的窗口。已完成／失败／暂停章节和
    /// 已写入磁盘的页都保留，新任务重新打开章节后按 manifest 只补缺失页。
    @discardableResult
    func requeueDownloadingChapters(for comic: ComicIdentity, now: Date) throws -> [ChapterIdentity] {
        var requeued: [ChapterIdentity] = []
        for stored in try fetchDownloads(for: comic) where stored.state == .downloading {
            guard let identity = stored.chapterIdentity else { continue }

            stored.state = .queued
            stored.jobID = nil
            stored.stateChangedAt = now
            requeued.append(identity)
        }
        guard !requeued.isEmpty else { return [] }

        markProjectionDirty(for: comic)
        try touchWorks(keys: [StoredDownloadedComic.key(for: comic)], now: now)
        try saveChanges()
        return requeued
    }

    /// 继续／重试一个作品：暂停章节与封面重新排队；`includeFailed` 为真时失败项也重排队。
    func requeueWork(for comic: ComicIdentity, includeFailed: Bool, now: Date) throws {
        let rows = try fetchDownloads(for: comic)
        var changed = false
        for row in rows {
            if row.state == .paused || (includeFailed && row.state == .failed) {
                row.state = .queued
                row.jobID = nil
                row.stateChangedAt = now
                changed = true
            }
        }
        if let work = try fetchWork(key: StoredDownloadedComic.key(for: comic)),
           work.coverState == .paused || (includeFailed && work.coverState == .failed) {
            work.coverState = .queued
            changed = true
        }
        guard changed else { return }

        markProjectionDirty(for: comic)
        try touchWorks(keys: [StoredDownloadedComic.key(for: comic)], now: now)
        try saveChanges()
    }
}

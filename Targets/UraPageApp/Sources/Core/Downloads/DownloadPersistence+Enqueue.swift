import Foundation
import SwiftData

// MARK: - 入队

extension DownloadPersistence {
    /// 新增／重试入队：确保作品行存在，并把未完成的章节置为 queued。
    ///
    /// 已完成、排队、下载、暂停中的章节不因重复入队被打断；失败章节视为重试重新排队。
    func upsert(requests: [DownloadChapterRequest], now: Date) throws {
        guard !requests.isEmpty else { return }

        do {
            var touchedComicKeys: Set<String> = []
            let requestsByComic = Dictionary(grouping: requests, by: \.identity.comic)
            let encoder = JSONEncoder()
            for (comic, comicRequests) in requestsByComic {
                let workKey = StoredDownloadedComic.key(for: comic)
                let snapshot = comicRequests[0].comicSnapshot
                let coverReferenceData = try encoder.encode(snapshot.cover)
                let detailExtrasData = try encoder.encode(DownloadedComicDetailExtras(snapshot: snapshot))
                let existingWork = try fetchWork(key: workKey)

                if let work = existingWork {
                    let existingCover = try JSONDecoder().decode(
                        ComicImageSource.self,
                        from: work.coverReferenceData,
                    )
                    if existingCover != snapshot.cover {
                        work.coverState = work.coverState == .paused
                            ? .paused
                            : Self.initialCoverState(for: snapshot.cover)
                    }
                    work.title = snapshot.title
                    work.authors = snapshot.authorNames
                    work.tags = snapshot.tags
                    work.categories = snapshot.categories
                    work.coverReferenceData = coverReferenceData
                    work.detailExtrasData = detailExtrasData
                } else {
                    modelContext.insert(
                        StoredDownloadedComic(
                            identity: comic,
                            title: snapshot.title,
                            authors: snapshot.authorNames,
                            tags: snapshot.tags,
                            categories: snapshot.categories,
                            coverReferenceData: coverReferenceData,
                            detailExtrasData: detailExtrasData,
                            coverState: Self.initialCoverState(for: snapshot.cover),
                            // 新章节全部按 queued 写入；聚合投影在本次事务保存前按章节行重算。
                            state: .queued,
                            completedChapterCount: 0,
                            chapterCount: comicRequests.count,
                            now: now,
                        ),
                    )
                }

                // 一次取出该作品已有章节，避免逐请求各查一次。
                var existingDownloads = try Dictionary(
                    uniqueKeysWithValues: fetchDownloads(for: comic).map { ($0.identityKey, $0) },
                )
                var didChangeTasks = existingWork == nil
                for request in comicRequests {
                    let identity = request.identity
                    if let existing = existingDownloads[StoredDownload.key(for: identity)] {
                        if existing.state == .failed {
                            existing.state = .queued
                            existing.jobID = nil
                            existing.stateChangedAt = now
                            didChangeTasks = true
                        }
                    } else {
                        let inserted = StoredDownload(request: request, state: .queued, jobID: nil, now: now)
                        modelContext.insert(inserted)
                        existingDownloads[inserted.identityKey] = inserted
                        didChangeTasks = true
                    }
                }
                // 只有真正新增或重新排队章节时才刷新未完成组顺序；重复点击已下载作品不改变位置。
                if let work = existingWork, didChangeTasks {
                    work.sortAt = now
                }
                touchedComicKeys.insert(workKey)
                markProjectionDirty(workKey: workKey)
            }
            try touchWorks(keys: touchedComicKeys, now: now)
            try saveChanges()
        } catch {
            pendingProjectionKeys.removeAll()
            modelContext.rollback()
            throw error
        }
    }
}

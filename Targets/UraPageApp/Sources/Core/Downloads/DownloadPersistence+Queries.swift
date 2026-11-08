import Foundation
import SwiftData

// MARK: - 查询

extension DownloadPersistence {
    /// 指定作品的全部章节记录，按目录顺序升序。
    func chapterRecords(for comic: ComicIdentity) throws -> [ChapterDownloadRecord] {
        let downloads = try fetchDownloads(for: comic)
        return downloads.compactMap(makeRecord).sorted { $0.order < $1.order }
    }

    /// 指定章节的记录（按完整身份查询）；记录缺失或损坏时返回 `nil`。
    func chapterRecord(for identity: ChapterIdentity) throws -> ChapterDownloadRecord? {
        try fetchDownload(key: StoredDownload.key(for: identity)).flatMap(makeRecord)
    }

    /// 持久化中的全部作品原始身份（含来源不可识别的记录），用于孤儿资产判定。
    func allAssetIdentities() throws -> [DownloadAssetIdentity] {
        try modelContext.fetch(FetchDescriptor<StoredDownloadedComic>()).map {
            DownloadAssetIdentity(sourceID: $0.sourceID, comicID: $0.comicID)
        }
    }

    /// 详情页下载状态：一次取回作品聚合投影与全部章节记录，避免两次查询。
    func downloadStatus(for comic: ComicIdentity) throws -> (
        summary: DownloadedComicSummary?,
        chapters: [ChapterDownloadRecord],
    ) {
        let chapters = try fetchDownloads(for: comic)
            .compactMap(makeRecord)
            .sorted { $0.order < $1.order }
        guard let work = try fetchWork(key: StoredDownloadedComic.key(for: comic)) else {
            return (nil, chapters)
        }

        return try (makeSummary(work: work), chapters)
    }

    func workDisplay(for comic: ComicIdentity) throws -> DownloadWorkDisplay? {
        guard let work = try fetchWork(key: StoredDownloadedComic.key(for: comic)),
              let coverState = work.coverState
        else { return nil }

        let source = try JSONDecoder().decode(ComicImageSource.self, from: work.coverReferenceData)

        return DownloadWorkDisplay(
            title: work.title,
            authors: work.authors,
            cover: downloadedCover(source: source, isAvailable: coverState == .completed),
            coverState: coverState,
        )
    }

    /// 离线详情记录：只有作品聚合状态为 `completed` 才返回，包含全部章节元信息。
    ///
    /// 离线详情由作品行列、`detailExtrasData` 与章节行组装；作品完成即代表所选章节与封面已全部落盘，
    /// 打开离线详情只信任这个持久化状态，不逐章读取 manifest 或复核文件完整性，避免检查拖慢详情加载；
    /// 部分章节／图片失败的作品聚合为 `failed`，不在此返回（由下载记录重试）。
    func offlineRecord(for comic: ComicIdentity) throws -> DownloadedComicDetailRecord? {
        guard let work = try fetchWork(key: StoredDownloadedComic.key(for: comic)),
              work.state == .completed
        else { return nil }

        let downloads = try fetchDownloads(for: comic)
        let extras = try JSONDecoder().decode(
            DownloadedComicDetailExtras.self,
            from: work.detailExtrasData,
        )
        let coverSource = try JSONDecoder().decode(
            ComicImageSource.self,
            from: work.coverReferenceData,
        )

        return DownloadedComicDetailRecord(
            detail: DownloadedComicDetailSnapshot(
                identity: comic,
                title: work.title,
                authorNames: work.authors,
                cover: downloadedCover(source: coverSource, isAvailable: work.coverState == .completed),
                extras: extras,
            ),
            chapters: downloads.compactMap(makeRecord).sorted { $0.order < $1.order },
        )
    }

    /// 冷启动时列出需要恢复封面传输的作品（只读作品行列的身份与封面引用）。
    func pendingCoverTransfers() throws -> [PendingCoverTransfer] {
        let queued = DownloadState.queued.rawValue
        let works = try modelContext.fetch(
            FetchDescriptor<StoredDownloadedComic>(
                predicate: #Predicate { $0.coverStateRawValue == queued },
            ),
        )
        var transfers: [PendingCoverTransfer] = []

        for work in works {
            do {
                if let transfer = try pendingCoverTransfer(for: work) {
                    transfers.append(transfer)
                }
            } catch {
                AppLogger.warning(
                    "下载作品封面引用无法恢复，errorType=\(String(reflecting: type(of: error)))",
                    category: "App.Download",
                )
            }
        }

        return transfers
    }

    /// 读取一个排队中作品的封面传输输入，供作品进入下载队列时使用。
    func pendingCoverTransfer(for comic: ComicIdentity) throws -> PendingCoverTransfer? {
        guard let work = try fetchWork(key: StoredDownloadedComic.key(for: comic)),
              work.coverState == .queued
        else { return nil }

        return try pendingCoverTransfer(for: work)
    }

    func summary(for comic: ComicIdentity) throws -> DownloadedComicSummary? {
        guard let work = try fetchWork(key: StoredDownloadedComic.key(for: comic)) else {
            return nil
        }

        return try makeSummary(work: work)
    }
}

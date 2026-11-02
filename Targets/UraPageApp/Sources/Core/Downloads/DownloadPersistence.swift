import Foundation
import SwiftData

/// 下载记录与离线详情的持久化 owner；在独立 SwiftData executor 上运行，只向上层返回 Sendable 值。
///
/// 职责按扩展拆分在同目录的 `DownloadPersistence+*.swift`：入队、查询、分页、删除、
/// 封面与调度状态；本文件只保留 actor 声明、启动装配与跨职责共享实现。
/// `@ModelActor` 的扩展不能新增存储属性，因此 `pendingProjectionKeys` 必须留在本文件。
@ModelActor
actor DownloadPersistence {
    /// 待重算聚合投影的作品 key；状态写入都在同一事务内刷新投影（单一写者，读取端只读投影）。
    var pendingProjectionKeys: Set<String> = []

    @concurrent
    static func makeDefault() async throws -> DownloadPersistence {
        let schema = Schema([StoredDownload.self, StoredDownloadedComic.self])
        return try DownloadPersistence(
            modelContainer: SwiftDataStoreContainer.make(
                schema: schema,
                name: "DownloadsV1",
                fileName: AppConfiguration.Persistence.downloadStore,
            ),
        )
    }

    // MARK: - 共享实现

    /// 重算作品聚合投影（状态 + 章节计数）；读取端只用投影，不再逐作品查章节行。
    ///
    /// 章节状态无法识别时不重算，保留上一次的有效投影，避免把损坏数据当成新状态。
    private func refreshWorkProjection(workKey: String) throws {
        guard let work = try fetchWork(key: workKey),
              let coverState = work.coverState
        else { return }

        let sourceID = work.sourceID
        let comicID = work.comicID
        let downloads = try modelContext.fetch(
            FetchDescriptor<StoredDownload>(
                predicate: #Predicate { $0.sourceID == sourceID && $0.comicID == comicID },
            ),
        )
        let states = downloads.compactMap(\.state)
        guard states.count == downloads.count else { return }

        let wasCompleted = work.state == .completed
        work.state = DownloadedComicSummary.aggregateState(states, coverState: coverState)
        work.completedChapterCount = states.filter { $0 == .completed }.count
        work.chapterCount = states.count

        // 首次完成：进入已完成组，用完成时刻排在组首；之后再补下章节会在入队时刷新未完成组时间。
        if work.state == .completed {
            if !wasCompleted {
                work.sortGroup = 1
                work.sortAt = Date()
            }
        } else {
            work.sortGroup = 0
        }
    }

    func markProjectionDirty(for comic: ComicIdentity) {
        markProjectionDirty(workKey: StoredDownloadedComic.key(for: comic))
    }

    func markProjectionDirty(workKey: String) {
        pendingProjectionKeys.insert(workKey)
    }

    /// 保存前刷新所有脏作品的投影；失败的标记随回滚一起丢弃。
    private func flushWorkProjections() throws {
        guard !pendingProjectionKeys.isEmpty else { return }

        let keys = pendingProjectionKeys
        pendingProjectionKeys.removeAll()
        for key in keys {
            try refreshWorkProjection(workKey: key)
        }
    }

    func fetchWork(key: String) throws -> StoredDownloadedComic? {
        var descriptor = FetchDescriptor<StoredDownloadedComic>(
            predicate: #Predicate { $0.identityKey == key },
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    /// 每个持久化操作都是独立事务；保存前先刷新作品聚合投影，失败时丢弃未提交变更与待刷新标记。
    func saveChanges() throws {
        do {
            try flushWorkProjections()
            try modelContext.save()
        } catch {
            pendingProjectionKeys.removeAll()
            modelContext.rollback()
            throw error
        }
    }

    func fetchDownload(key: String) throws -> StoredDownload? {
        var descriptor = FetchDescriptor<StoredDownload>(
            predicate: #Predicate { $0.identityKey == key },
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    func fetchDownloads(for comic: ComicIdentity) throws -> [StoredDownload] {
        let sourceID = comic.sourceID.rawValue
        let comicID = comic.comicID
        return try modelContext.fetch(
            FetchDescriptor<StoredDownload>(
                predicate: #Predicate { $0.sourceID == sourceID && $0.comicID == comicID },
                sortBy: [SortDescriptor(\StoredDownload.chapterOrderSnapshot)],
            ),
        )
    }

    /// 章节行归属的作品 key；与 `StoredDownloadedComic.key(sourceID:comicID:)` 同一编码。
    static func workKey(of download: StoredDownload) -> String {
        StoredDownloadedComic.key(sourceID: download.sourceID, comicID: download.comicID)
    }

    func touchWorks(keys: Set<String>, now: Date) throws {
        for key in keys {
            if let work = try fetchWork(key: key) {
                work.updatedAt = now
            }
        }
    }

    func makeRecord(_ stored: StoredDownload) -> ChapterDownloadRecord? {
        guard let identity = stored.chapterIdentity,
              let state = stored.state
        else {
            return nil
        }

        return ChapterDownloadRecord(
            identity: identity,
            title: stored.chapterTitleSnapshot,
            order: stored.chapterOrderSnapshot,
            state: state,
        )
    }

    /// 作品行聚合投影转展示值；列表与按作品读取共用，不再查章节行。
    ///
    /// 身份、聚合状态、封面状态或封面引用无法读取时按损坏记录跳过／抛错，不用默认状态掩盖。
    func makeSummary(work: StoredDownloadedComic) throws -> DownloadedComicSummary? {
        guard let identity = work.identity,
              let state = work.state,
              let coverState = work.coverState
        else { return nil }

        let source = try JSONDecoder().decode(ComicImageSource.self, from: work.coverReferenceData)
        return DownloadedComicSummary(
            identity: identity,
            title: work.title,
            authors: work.authors,
            cover: downloadedCover(source: source, isAvailable: coverState == .completed),
            state: state,
            completedChapterCount: work.completedChapterCount,
            chapterCount: work.chapterCount,
            // 进度是运行时的单位计数；未运行时只按状态展示。
            progress: nil,
            updatedAt: work.updatedAt,
        )
    }

    func downloadedCover(
        source: ComicImageSource,
        isAvailable: Bool,
    ) -> ComicImageSource {
        guard isAvailable else {
            return .downloaded(reference: nil)
        }

        let reference: ComicImageReference?
        switch source {
        case let .remote(value):
            reference = value
        case let .downloaded(reference: value):
            reference = value
        }
        return .downloaded(reference: reference)
    }

    static func initialCoverState(for cover: ComicImageSource) -> DownloadState {
        switch cover {
        case .remote:
            .queued
        case let .downloaded(reference: reference):
            reference == nil ? .failed : .completed
        }
    }
}

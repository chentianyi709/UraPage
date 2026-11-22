import Foundation
import SwiftData

/// 下载记录与离线详情的持久化 owner；在独立 SwiftData executor 上运行，只向上层返回 Sendable 值。
///
/// 职责按扩展拆分在同目录的 `DownloadPersistence+*.swift`：入队、查询、分页、删除、
/// 封面与调度状态；本文件只保留 actor 声明、启动装配与跨职责共享实现。
/// `@ModelActor` 的扩展不能新增存储属性，因此 `pendingProjectionKeys` 必须留在本文件。
@ModelActor
actor DownloadPersistence {
    /// 待重算聚合投影的作品；状态写入都在同一事务内刷新投影（单一写者，读取端只读投影）。
    var pendingProjectionKeys: Set<DownloadWorkKey> = []

    /// 逐行解码封面引用用的解码器：列表一次要解几十行，不必每行新建一个。
    /// 只在 actor 内同步使用，不跨隔离域共享。
    private let jsonDecoder = JSONDecoder()

    @concurrent
    static func makeDefault() async throws -> DownloadPersistence {
        let schema = Schema([StoredDownloadChapter.self, StoredDownloadWork.self])
        return try DownloadPersistence(
            modelContainer: SwiftDataStoreContainer.make(
                schema: schema,
                name: "DownloadsV2",
                fileName: AppConfiguration.Persistence.downloadStore,
            ),
        )
    }

    // MARK: - 共享实现

    /// 重算作品聚合投影（状态 + 章节计数）；读取端只用投影，不再逐作品查章节行。
    ///
    /// 按状态计数而不是取回全部章节行：200 章作品单次重算 4.97 ms → 0.88 ms（2026-11-22 探针），
    /// 且成本几乎不随章节数增长。总数与各状态计数之和不一致（有无法识别的状态）时不重算，
    /// 保留上一次的有效投影，避免把损坏数据当成新状态。
    private func refreshWorkProjection(for key: DownloadWorkKey) throws {
        guard let work = try fetchWork(key),
              let coverState = work.coverState
        else { return }

        let total = try modelContext.fetchCount(chapterDescriptor(for: key))
        var counts: [DownloadState: Int] = [:]
        var known = 0
        for state in DownloadState.allCases {
            let count = try modelContext.fetchCount(chapterDescriptor(for: key, state: state))
            counts[state] = count
            known += count
        }
        guard known == total else { return }

        work.applyProjection(
            state: DownloadedComicSummary.aggregateState(counts: counts, coverState: coverState),
            completedChapterCount: counts[.completed] ?? 0,
            chapterCount: total,
            now: Date(),
        )
    }

    /// 按作品取章节的描述符；给定状态时只数该状态的行。
    private func chapterDescriptor(
        for key: DownloadWorkKey,
        state: DownloadState? = nil,
    ) -> FetchDescriptor<StoredDownloadChapter> {
        let sourceID = key.sourceID
        let comicID = key.comicID
        guard let state else {
            return FetchDescriptor(
                predicate: #Predicate { $0.sourceID == sourceID && $0.comicID == comicID },
            )
        }

        let raw = state.rawValue
        return FetchDescriptor(
            predicate: #Predicate {
                $0.sourceID == sourceID && $0.comicID == comicID && $0.stateRawValue == raw
            },
        )
    }

    func markProjectionDirty(for comic: ComicIdentity) {
        pendingProjectionKeys.insert(DownloadWorkKey(comic))
    }

    func markProjectionDirty(_ key: DownloadWorkKey) {
        pendingProjectionKeys.insert(key)
    }

    /// 保存前刷新所有脏作品的投影；失败的标记随回滚一起丢弃。
    private func flushWorkProjections() throws {
        guard !pendingProjectionKeys.isEmpty else { return }

        let keys = pendingProjectionKeys
        pendingProjectionKeys.removeAll()
        for key in keys {
            try refreshWorkProjection(for: key)
        }
    }

    func fetchWork(_ key: DownloadWorkKey) throws -> StoredDownloadWork? {
        let sourceID = key.sourceID
        let comicID = key.comicID
        var descriptor = FetchDescriptor<StoredDownloadWork>(
            predicate: #Predicate { $0.sourceID == sourceID && $0.comicID == comicID },
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    func fetchWork(for comic: ComicIdentity) throws -> StoredDownloadWork? {
        try fetchWork(DownloadWorkKey(comic))
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

    func fetchDownload(for identity: ChapterIdentity) throws -> StoredDownloadChapter? {
        let sourceID = identity.comic.sourceID.rawValue
        let comicID = identity.comic.comicID
        let chapterID = identity.chapterID
        var descriptor = FetchDescriptor<StoredDownloadChapter>(
            predicate: #Predicate {
                $0.sourceID == sourceID && $0.comicID == comicID && $0.chapterID == chapterID
            },
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    func fetchDownloads(for comic: ComicIdentity) throws -> [StoredDownloadChapter] {
        let sourceID = comic.sourceID.rawValue
        let comicID = comic.comicID
        return try modelContext.fetch(
            FetchDescriptor<StoredDownloadChapter>(
                predicate: #Predicate { $0.sourceID == sourceID && $0.comicID == comicID },
                sortBy: [SortDescriptor(\StoredDownloadChapter.chapterOrderSnapshot)],
            ),
        )
    }

    /// 章节行归属的作品；与 `DownloadWorkKey(ComicIdentity)` 同一对原始字段。
    static func workKey(of download: StoredDownloadChapter) -> DownloadWorkKey {
        DownloadWorkKey(sourceID: download.sourceID, comicID: download.comicID)
    }

    func makeRecord(_ stored: StoredDownloadChapter) -> ChapterDownloadRecord? {
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
    func makeSummary(work: StoredDownloadWork) throws -> DownloadedComicSummary? {
        guard let identity = work.identity,
              let state = work.state,
              let coverState = work.coverState
        else { return nil }

        let source = try jsonDecoder.decode(ComicImageSource.self, from: work.coverReferenceData)
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

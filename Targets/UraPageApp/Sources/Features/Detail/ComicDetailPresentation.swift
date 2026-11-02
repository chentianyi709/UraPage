/// 同一详情界面使用的展示状态；在线模型与下载快照都先映射到这份值。
struct ComicDetailPresentation: Sendable {
    let detail: DownloadedComicDetailSnapshot
    /// Reader 顺序；来源可在真实目录缺失时提供仅供阅读的单话章节。
    let readerChapters: [DownloadChapterCandidate]
    /// 可加入下载队列的章节；由来源按下载接口实际支持范围映射。
    let downloadCandidates: [DownloadChapterCandidate]
    /// 章节弹窗实际展示的目录，不包含仅供阅读／下载的合成章节。
    let chapterPickerChapters: [DownloadChapterCandidate]
    let relatedComics: [ComicListItem]
    let isLiked: Bool

    init(
        detail: DownloadedComicDetailSnapshot,
        readerChapters: [DownloadChapterCandidate],
        downloadCandidates: [DownloadChapterCandidate],
        chapterPickerChapters: [DownloadChapterCandidate],
        relatedComics: [ComicListItem] = [],
        isLiked: Bool = false,
    ) {
        self.detail = detail
        self.readerChapters = readerChapters
        self.downloadCandidates = downloadCandidates
        self.chapterPickerChapters = chapterPickerChapters
        self.relatedComics = relatedComics
        self.isLiked = isLiked
    }

    /// 离线详情只展示下载状态已完成的章节；Reader 按 manifest 读取其页面文件。
    init(_ record: DownloadedComicDetailRecord) {
        detail = record.detail
        readerChapters = record.chapters.map {
            DownloadChapterCandidate(identity: $0.identity, title: $0.title, order: $0.order)
        }
        downloadCandidates = readerChapters
        chapterPickerChapters = readerChapters
        relatedComics = []
        isLiked = false
    }

    /// 是否展示底部操作栏：在线始终展示；离线只在有可用的章节入口时保留（章节入口在右）。
    ///
    /// 模式由页面入参提供，展示值不保存第二份，避免在线／离线状态分叉。
    func showsBottomBar(mode: ComicContentMode) -> Bool {
        mode == .online || showsChapterEntry
    }

    /// 是否展示章节入口（详情按钮条件与非空目录）；底栏、章节入口按钮与下载入口共用同一判定。
    var showsChapterEntry: Bool {
        detail.showsChaptersButton && !chapterPickerChapters.isEmpty
    }

    /// 三来源详情共用同一份离线快照加载规则。
    @MainActor
    static func makeOfflineLoadModel(
        manager: DownloadManager,
        identity: ComicIdentity,
        logCategory: String,
    ) -> SourceValueLoadModel<Self> {
        SourceValueLoadModel(logCategory: logCategory) {
            guard let record = try await manager.offlineDetail(for: identity) else {
                throw ComicSourceError.invalidIdentity
            }

            return Self(record)
        }
    }

    /// 用当前展示状态创建共用 Reader 输入，确保章节列表与在线／离线模式成对传递。
    func makeReaderInput(
        for chapter: DownloadChapterCandidate,
        mode: ComicContentMode,
        startPosition: ReaderStartPosition? = nil,
    ) -> ComicReaderInput? {
        ComicReaderInput(
            comicSnapshot: ReaderComicSnapshot(detail: detail),
            startPosition: startPosition,
            chapters: readerChapters.map {
                ReaderChapterReference(identity: $0.identity, title: $0.title)
            },
            initialChapterIdentity: chapter.identity,
            contentMode: mode,
        )
    }
}

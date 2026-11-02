import Foundation
import Observation

/// 离线会话的读取能力必须成组提供，避免只传部分参数时意外进入在线分支。
struct ReaderDownloadedContent: Sendable {
    let sessionMemoryNamespace: UUID
    let payload: ReaderPageAccess.DownloadedPayload
    let close: @Sendable () async -> Void
}

/// 描述菜单切章请求，不与首次进入页面的加载状态混用。
enum ReaderChapterSwitchState: Equatable {
    case idle
    case loading(ChapterIdentity)
    case failed

    /// 返回正在请求的目标章节。
    var loadingChapterIdentity: ChapterIdentity? {
        guard case let .loading(identity) = self else {
            return nil
        }

        return identity
    }
}

/// 描述 Reader 相邻章节边界当前的加载状态。
enum ReaderAdjacentChapterLoadState: Equatable {
    case idle
    case loading
    case failed
}

/// 把已打开章节的来源句柄与完整逻辑槽位绑定；真实身份由页面任务按需解析。
nonisolated struct ReaderOpenedChapter: Sendable {
    let source: any SourceOpenedChapter
    let slots: [ReaderPageSlot]

    /// 返回来源句柄持有的章节内容。
    var content: SourceChapterContent {
        source.content
    }
}

/// 同一章节的首批请求由菜单与相邻章加载共享，切章只更换展示意图。
nonisolated struct ReaderChapterRequest: Sendable {
    let id = UUID()
    let task: Task<ReaderOpenedChapter, any Error>
}

/// 三来源共用的章节窗口和异步任务 owner。
/// 单章是只有一个引用的窗口；相邻章节检查自然到达边界，不再维护一套单章加载逻辑。
@Observable
@MainActor
final class ComicReaderViewModel {
    let input: ComicReaderInput

    var chapters: [SourceChapterContent] = []
    var pages: [ReaderPageSlot] = []
    var loadState: InitialLoadState<SourceLoadDisplayError> = .idle
    var chapterSwitchState: ReaderChapterSwitchState = .idle
    var currentPage: ReaderPageSlot?
    var scrollRequest: ReaderCanvasScrollRequest?
    var previousChapterLoadState: ReaderAdjacentChapterLoadState = .idle
    var nextChapterLoadState: ReaderAdjacentChapterLoadState = .idle

    @ObservationIgnored
    let openChapter: @Sendable (ChapterIdentity) async throws -> any SourceOpenedChapter

    @ObservationIgnored
    let loadOnlinePage: ReaderPageAccess.OnlineChapterPageLoader

    @ObservationIgnored
    let downloadedContent: ReaderDownloadedContent?

    /// 输入章节 identity 到最旧至最新顺序下标的查找表。
    @ObservationIgnored
    let chapterIndexByID: [ChapterIdentity: Int]

    @ObservationIgnored
    var loadTask: Task<Void, Never>?

    @ObservationIgnored
    let taskRetirement = ReaderTaskRetirement()

    @ObservationIgnored
    var previousChapterTask: Task<Void, Never>?

    @ObservationIgnored
    var nextChapterTask: Task<Void, Never>?

    @ObservationIgnored
    var loadGeneration = 0

    @ObservationIgnored
    var earliestChapterIndex: Int?

    @ObservationIgnored
    var latestChapterIndex: Int?

    @ObservationIgnored
    var scrollRequestSerial = 0

    @ObservationIgnored
    private(set) var contentVersion = 0

    @ObservationIgnored
    private(set) var replacementVersion = 0

    @ObservationIgnored
    var openedChapters: [ChapterIdentity: ReaderOpenedChapter] = [:]

    @ObservationIgnored
    var chapterRequests: [ChapterIdentity: ReaderChapterRequest] = [:]

    /// 使用已校验输入和来源提供的章节打开操作创建页面状态。
    init(
        input: ComicReaderInput,
        openChapter: @escaping @Sendable (ChapterIdentity) async throws -> any SourceOpenedChapter,
        loadOnlinePage: @escaping ReaderPageAccess.OnlineChapterPageLoader,
        downloadedContent: ReaderDownloadedContent? = nil,
    ) {
        self.input = input
        self.openChapter = openChapter
        self.loadOnlinePage = loadOnlinePage
        self.downloadedContent = downloadedContent
        chapterIndexByID = Dictionary(
            uniqueKeysWithValues: input.chapters.enumerated().map {
                ($0.element.identity, $0.offset)
            },
        )
    }

    deinit {
        loadTask?.cancel()
        previousChapterTask?.cancel()
        nextChapterTask?.cancel()
        chapterRequests.values.forEach { $0.task.cancel() }
    }

    /// 完整替换 Canvas 页面并发布一次内容代次。
    func replacePages(_ pages: [ReaderPageSlot]) {
        self.pages = pages
        contentVersion &+= 1
        replacementVersion = contentVersion
    }

    /// 把相邻下一章增量追加到已加载内容。
    func appendPages(_ newPages: [ReaderPageSlot]) {
        guard !newPages.isEmpty else {
            return
        }

        pages.append(contentsOf: newPages)
        contentVersion &+= 1
    }

    /// 把相邻上一章增量插入已加载内容顶部。
    func prependPages(_ newPages: [ReaderPageSlot]) {
        guard !newPages.isEmpty else {
            return
        }

        pages.insert(contentsOf: newPages, at: 0)
        contentVersion &+= 1
    }
}

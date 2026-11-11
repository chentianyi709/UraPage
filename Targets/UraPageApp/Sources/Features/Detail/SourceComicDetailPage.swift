import SwiftUI

/// 三来源共用的详情页骨架：在线／离线加载、阅读进度、底栏、选章、下载与 Reader 入口。
///
/// 来源只提供三件事：
/// 1. 把本源详情映射成 `ComicDetailPresentation`；
/// 2. 声明本源 route 的导航值（Bika 的贡献者/分类、Shenshi 的发布者/标签等）如何解码；
/// 3. 作者、分类、标签、Reader 与相关推荐要 push 到本源哪条 route。
///
/// 页面状态（加载、进度、下载控制器、章节弹窗）由本类型统一持有；来源不再各自复制
/// `.task` 链、底栏与章节选择接线。`Related` 是来源自己的推荐区，页面只负责放在详情末尾。
struct SourceComicDetailPage<Navigation: Decodable & Sendable, Related: View>: View {
    @Environment(\.readerProgressRecorder) private var progressRecorder
    @Environment(\.downloadManager) private var downloadManager
    @Environment(\.appShell) private var shell

    /// 详情身份与在线／离线模式；离线只读下载快照。
    let identity: ComicIdentity
    let mode: ComicContentMode

    /// 在线详情加载；离线模式不会调用。
    let loadPresentation: @Sendable (ComicIdentity) async throws -> ComicDetailPresentation

    /// 解码本源的详情导航值；没有额外导航身份的来源返回空值即可。
    let decodeNavigation: (DownloadedComicDetailSnapshot) throws -> Navigation

    /// 作者行点击：`index` 是来源作者数组下标，`name` 是展示名。
    let onSelectAuthor: (ComicDetailPresentation, Navigation?, Int, String) -> Void

    /// 标签组胶囊点击：维度由来源详情给出，名称是清理过空白的展示值。
    let onSelectTag: (ComicDetailPresentation, Navigation?, ComicTagKind, String) -> Void

    /// 作品 ID 复制入口；`nil` 表示本源不提供复制。
    let copyContentProvider: ComicDetailCopyProvider?

    /// 点赞动作；`nil` 表示本源未接入点赞（不显示按钮）。
    let likeAction: ComicDetailLikeAction?

    /// 打开 Reader；页面已根据当前展示解析好 `ComicReaderInput`。
    let onOpenReader: (ComicReaderInput) -> Void

    /// 相关推荐区；来源自行决定在线／离线是否展示。
    @ContentBuilder let related: (ComicDetailPresentation) -> Related

    /// 详情值加载完成后的一次性回调（例如 Bika 记录推荐跳转）；不参与页面布局。
    let onPresentationLoaded: ((ComicDetailPresentation) -> Void)?

    /// 日志分类，例如 `"Bika.Detail"`；只用于本页模型与错误日志。
    let logCategory: String

    @State private var model: SourceValueLoadModel<ComicDetailPresentation>?
    @State private var readingProgress: ReadingProgress?
    @State private var isChaptersSheetPresented = false
    @State private var downloadController: ComicDownloadController?
    @State private var navigation: Navigation?
    @State private var isLiking = false
    @State private var likedOverride: Bool?

    init(
        identity: ComicIdentity,
        mode: ComicContentMode,
        loadPresentation: @escaping @Sendable (ComicIdentity) async throws -> ComicDetailPresentation,
        decodeNavigation: @escaping (DownloadedComicDetailSnapshot) throws -> Navigation,
        onSelectAuthor: @escaping (ComicDetailPresentation, Navigation?, Int, String) -> Void,
        onSelectTag: @escaping (ComicDetailPresentation, Navigation?, ComicTagKind, String) -> Void,
        copyContentProvider: ComicDetailCopyProvider?,
        likeAction: ComicDetailLikeAction? = nil,
        onOpenReader: @escaping (ComicReaderInput) -> Void,
        onPresentationLoaded: ((ComicDetailPresentation) -> Void)? = nil,
        logCategory: String,
        @ContentBuilder related: @escaping (ComicDetailPresentation) -> Related,
    ) {
        self.identity = identity
        self.mode = mode
        self.loadPresentation = loadPresentation
        self.decodeNavigation = decodeNavigation
        self.onSelectAuthor = onSelectAuthor
        self.onSelectTag = onSelectTag
        self.copyContentProvider = copyContentProvider
        self.likeAction = likeAction
        self.onOpenReader = onOpenReader
        self.onPresentationLoaded = onPresentationLoaded
        self.logCategory = logCategory
        self.related = related
    }

    var body: some View {
        InitialValueLoadView(
            model: model,
            initialState: { $0.loadState },
        ) {
            ComicDetailSkeletonView(showsRelated: mode == .online)
        } failure: { model, error in
            LoadErrorView(title: "详情加载失败", message: error.message) {
                model.retry()
            }
        } content: { presentation in
            let detail = presentation.detail
            let continuation = readingProgress.flatMap { progress in
                presentation.readerChapters
                    .first(where: { $0.identity == progress.pageIdentity.chapter })
                    .map { (progress, $0) }
            }
            ComicDetailContentView(
                detail: detail,
                onStartReading: presentation.readerChapters.first.map { chapter in
                    { openReader(presentation, chapter: chapter) }
                },
                readingProgress: continuation.map {
                    ComicDetailReadingProgress($0.0, chapterTitle: $0.1.title)
                },
                hasMultipleChapters: presentation.readerChapters.count > 1,
                onContinueReading: continuation.map { value in
                    { openReader(presentation, chapter: value.1, startPosition: value.0.readerStartPosition) }
                },
                onSelectAuthorName: { index, name in
                    onSelectAuthor(presentation, navigation, index, name)
                },
                onSelectTag: { kind, name in
                    onSelectTag(presentation, navigation, kind, name)
                },
                copyContentProvider: copyContentProvider,
                related: {
                    related(presentation)
                },
            )
        }
        .comicDetailChrome(
            title: model?.value?.detail.title,
            menuActions: menuActions,
        )
        .toolbar(content: makeBottomToolbar)
        .toolbarVisibility(shouldShowBottomBar ? .visible : .hidden, for: .bottomBar)
        .comicDetailChapterPicker(
            isPresented: $isChaptersSheetPresented,
            chapters: model?.value?.chapterPickerChapters ?? [],
            title: \.title,
            lastReadChapterID: readingProgress?.pageIdentity.chapter,
            onSelect: { chapter in
                if let presentation = model?.value {
                    openReader(presentation, chapter: chapter)
                }
            },
        )
        .comicDetailDownload(
            controller: $downloadController,
            identity: identity,
            contentMode: mode,
            chapters: model?.value?.downloadCandidates ?? [],
            snapshot: model?.value?.detail,
        )
        .task {
            prepareModelIfNeeded()
            model?.loadIfNeeded()
        }
        .task {
            await refreshReadingProgress()
        }
        .task(id: model?.value?.detail.identity) {
            guard let presentation = model?.value else { return }

            onPresentationLoaded?(presentation)
            do {
                navigation = try decodeNavigation(presentation.detail)
            } catch {
                navigation = nil
                AppLogger.error(
                    "详情导航数据解析失败，errorType=\(String(reflecting: type(of: error)))",
                    category: logCategory,
                )
            }
        }
    }

    /// 首次展示时创建页面状态 owner；重新进入详情复用同一实例。
    private func prepareModelIfNeeded() {
        guard model == nil else {
            return
        }

        if mode == .offline {
            model = ComicDetailPresentation.makeOfflineLoadModel(
                manager: downloadManager,
                identity: identity,
                logCategory: "\(logCategory).Offline",
            )
        } else {
            let loadPresentation = loadPresentation
            let identity = identity
            model = SourceValueLoadModel(logCategory: logCategory) {
                try await loadPresentation(identity)
            }
        }
    }

    /// 离线详情的「查看在线详情」：把同一作品按在线模式再 push 一层，返回即回到离线页。
    ///
    /// 走公共跨来源入口，由目标来源自己解析成本源路由；未登录来源的登录门禁在
    /// destination 边界生效（在线路由不再声明 `usesLocalAssetsOnly`），页面不重复判断。
    private func openOnlineDetail() {
        do {
            try shell.navigator.open(.detail(identity))
        } catch {
            AppLogger.error(
                "在线详情路由失败，errorType=\(String(reflecting: type(of: error)))",
                category: logCategory,
            )
            ToastCenter.shared.show("无法打开在线详情", type: .error)
        }
    }

    /// 详情页工具栏「更多操作」：按内容模式组装当前可用动作。
    ///
    /// 目前只有离线详情有动作，在线详情数组为空、工具栏不显示更多按钮。
    /// 菜单只放当前作品／来源的次要操作，不重复底栏与内容区入口；不可用动作直接不加入数组。
    /// 破坏性动作标 `isDestructive`，由页面自己在动作里做二次确认。
    private var menuActions: [ComicDetailMenuAction] {
        guard mode == .offline else { return [] }

        return [
            ComicDetailMenuAction(
                title: "查看在线详情",
                systemImage: "globe",
                action: {
                    openOnlineDetail()
                },
            ),
        ]
    }

    private func openReader(
        _ presentation: ComicDetailPresentation,
        chapter: DownloadChapterCandidate,
        startPosition: ReaderStartPosition? = nil,
    ) {
        guard let input = presentation.makeReaderInput(
            for: chapter,
            mode: mode,
            startPosition: startPosition,
        ) else {
            return
        }

        onOpenReader(input)
    }

    /// 读取阅读进度；失败只记录，不影响详情正文。
    private func refreshReadingProgress() async {
        do {
            readingProgress = try await progressRecorder.detailProgress(
                for: identity,
                contentMode: mode,
            )
        } catch is CancellationError {
            return
        } catch {
            AppLogger.error(
                "详情阅读进度读取失败，errorType=\(String(reflecting: type(of: error)))",
                category: logCategory,
            )
        }
    }

    /// 底部操作栏：点赞动作由来源注入，其余未接入的写操作保持 `nil`。
    private func makeBottomToolbar() -> ComicDetailBottomToolbar {
        let onLike: (() -> Void)? = if likeAction == nil {
            nil
        } else {
            handleLikeTap
        }

        return ComicDetailBottomToolbar(
            showsOnlineActions: mode == .online,
            isLiked: likedOverride ?? model?.value?.isLiked ?? false,
            isLiking: isLiking,
            onLike: onLike,
            onFavorite: nil,
            onDownload: handleDownloadTap,
            onChapters: model?.value?.showsChapterEntry == true
                ? { isChaptersSheetPresented = true }
                : nil,
            onComments: nil,
            downloadState: downloadController?.workState,
        )
    }

    /// 提交当前详情点赞；请求不随页面消失取消，但只把结果应用到同一作品。
    private func handleLikeTap() {
        guard !isLiking,
              let likeAction,
              let presentation = model?.value
        else {
            return
        }

        let identity = presentation.detail.identity
        let isLiked = likedOverride ?? presentation.isLiked

        // 不可取消点赞的来源在已点赞时只提示，不重复提交请求。
        if !likeAction.allowsUnliking, isLiked {
            ToastCenter.shared.show("已点赞", type: .info)
            return
        }

        isLiking = true

        Task {
            defer { isLiking = false }

            do {
                let result = try await likeAction.perform(identity)
                guard model?.value?.detail.identity == identity else { return }

                applyLikeResult(result)
            } catch is CancellationError {
                return
            } catch let error as ComicSourceError {
                guard model?.value?.detail.identity == identity else { return }

                ToastCenter.shared.show(
                    SourceLoadDisplayError(error).message,
                    type: .error,
                )
            } catch {
                guard model?.value?.detail.identity == identity else { return }

                ToastCenter.shared.show("点赞失败，请稍后重试", type: .error)
            }
        }
    }

    /// 只采用服务端确认后的状态，并在成功、取消成功与业务拒绝间区分提示类型。
    private func applyLikeResult(_ result: ComicDetailLikeResult) {
        switch result {
        case let .liked(message):
            likedOverride = true
            ToastCenter.shared.show(message ?? "点赞成功", type: .success)

        case let .unliked(message):
            likedOverride = false
            ToastCenter.shared.show(message ?? "已取消点赞", type: .success)

        case let .rejected(message):
            ToastCenter.shared.show(message ?? "点赞失败", type: .warning)
        }
    }

    private func handleDownloadTap() {
        guard let presentation = model?.value else {
            return
        }

        Task {
            await downloadController?.handleDownloadTap(
                chapters: presentation.downloadCandidates,
                snapshot: presentation.detail,
                presentsChapterSelection: presentation.showsChapterEntry,
            )
        }
    }

    private var shouldShowBottomBar: Bool {
        model?.value?.showsBottomBar(mode: mode) ?? false
    }
}

/// 没有额外详情导航身份的来源使用它（例如禁漫）。
struct EmptyDetailNavigation: Decodable, Sendable {}

/// 详情页点赞动作：来源声明是否支持取消点赞，并提交服务端确认的请求。
struct ComicDetailLikeAction: Sendable {
    /// 是否允许再次点击取消点赞。
    ///
    /// 为 `false` 时公共页面在已点赞状态下只提示「已点赞」，不发起请求；来源无需自行判断当前状态。
    let allowsUnliking: Bool

    /// 提交点赞或取消点赞；返回服务端确认后的结果。
    let perform: @Sendable (ComicIdentity) async throws -> ComicDetailLikeResult
}

/// 详情页点赞动作的服务端确认结果。
enum ComicDetailLikeResult: Sendable {
    /// 服务端确认已点赞；`message` 为空时使用默认成功提示。
    case liked(message: String?)

    /// 服务端确认已取消点赞（仅可切换点赞的来源）。
    case unliked(message: String?)

    /// 服务端拒绝，点赞状态保持不变。
    case rejected(message: String?)
}

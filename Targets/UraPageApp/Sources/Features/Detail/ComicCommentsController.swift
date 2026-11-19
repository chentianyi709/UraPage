import Observation
import SwiftUI

/// 评论页的来源能力：分页读取顶级评论，必要时按需读取某条评论的回复。
///
/// 回复随顶级评论一起返回的来源（禁漫、绅士）把 `loadReplies` 传 `nil`；
/// 需要单独接口的来源（哔咔）提供它，由评论行在展开时按需请求。
struct ComicCommentsProvider: Sendable {
    /// 读取第 `page` 页顶级评论，页码从 1 开始。
    let loadPage: @Sendable (_ page: Int) async throws -> ComicCommentPage

    /// 按需读取某条评论的第 `page` 页回复。
    let loadReplies: (@Sendable (_ commentID: String, _ page: Int) async throws -> ComicCommentPage)?

    init(
        loadPage: @escaping @Sendable (_ page: Int) async throws -> ComicCommentPage,
        loadReplies: (@Sendable (_ commentID: String, _ page: Int) async throws -> ComicCommentPage)? = nil,
    ) {
        self.loadPage = loadPage
        self.loadReplies = loadReplies
    }
}

/// 评论弹窗的页面级状态 owner：首屏、向上分页与按需回复都由它持有。
///
/// 与详情页的点赞／下载控制器同构：页面只负责展示，状态与请求都留在 owner 里。
@MainActor
@Observable
final class ComicCommentsController {
    /// 单条评论的按需回复状态；只有需要单独请求回复的来源才会有条目。
    ///
    /// 是否还有下一页由每次请求的 `ComicCommentPage.hasMore` 决定；来源给不出时
    /// 按累计条数与总数折算，空页或整页重复一律判停，不会让「加载更多回复」一直可点。
    struct ReplyState: Equatable {
        fileprivate(set) var comments: [ComicComment] = []
        fileprivate(set) var page = 0
        fileprivate(set) var isLoading = false
        fileprivate(set) var errorMessage: String?

        /// 还有下一页；空页或整页重复时立刻置 false。
        fileprivate(set) var hasMore = true

        /// 还有未取得的回复。
        var canLoadMore: Bool {
            hasMore
        }

        /// 有没有要展示的状态（加载中／失败／还有更多）；都为空时这行整行不占位。
        var hasVisibleStatus: Bool {
            isLoading || errorMessage != nil || canLoadMore
        }
    }

    private(set) var loadState: InitialLoadState<SourceLoadDisplayError> = .idle
    private(set) var comments: [ComicComment] = []

    /// 服务端声明的评论总数；来源不提供时为 0。只用于标题。
    private(set) var total = 0
    private(set) var isLoadingMore = false
    private(set) var loadMoreErrorMessage: String?

    /// 按顶级评论 ID 保存的按需回复状态。
    private(set) var replies: [String: ReplyState] = [:]

    private let provider: ComicCommentsProvider

    /// 已取得的最后一个页码；0 表示还没成功取过任何一页。
    private var page = 0
    private var hasMorePages = true

    /// 评论列表的代次：每次重新加载第 1 页递增，用来丢弃迟到的回复状态写回。
    @ObservationIgnored
    private var repliesGeneration = 0

    /// 正在进行的第 1 页请求；请求归 controller 持有，不随视图出现／消失启停。
    @ObservationIgnored
    private var loadTask: Task<Void, Never>?

    /// 第 1 页请求的代次：任务结束时按代次清理句柄，避免把新任务误清。
    @ObservationIgnored
    private var loadGeneration = 0

    /// 上一次分页失败的页码；同一页再次失败就判停，避免页脚永远停在必然失败的重试上。
    @ObservationIgnored
    private var failedLoadMorePage: Int?

    init(provider: ComicCommentsProvider) {
        self.provider = provider
    }

    /// 回复是否来自单独接口；为 `false` 时回复已经随顶级评论一起取得。
    var supportsRemoteReplies: Bool {
        provider.loadReplies != nil
    }

    /// 还有下一页顶级评论可加载。
    var canLoadMoreComments: Bool {
        loadState == .loaded && hasMorePages
    }

    /// 正在重新加载第 1 页；首屏与刷新共用骨架，工具栏图标也据此换成转圈。
    var isReloading: Bool {
        loadState == .loading
    }

    /// 分页页脚是否需要占位：只有一页评论时不渲染，免得结尾挂一句没有信息量的「没有更多了」。
    ///
    /// 不看 `hasMorePages`——还有下一页但仍在第 1 页时，页脚本来就不可见，渲染出来也是零高度。
    var showsPaginationFooter: Bool {
        isLoadingMore || loadMoreErrorMessage != nil || page > 1
    }

    /// 打开弹窗前注入详情给出的评论总数。
    ///
    /// 只有还没取过评论（`.idle`）时接收：已经加载过的不再被详情数据覆盖。
    /// 为 0 时直接落到空列表，省掉一次注定返回空的请求；`nil` 或大于 0 都照常请求。
    func applyCommentCount(_ count: Int?) {
        guard loadState == .idle, let count, count == 0 else {
            return
        }

        total = 0
        comments = []
        loadState = .loaded
    }

    /// 弹窗展示时触发首屏加载；已有结果或请求在途时直接返回。
    ///
    /// 失败过的页面重新打开会再试一次：用户关掉再进来，多半已经换了网络或 Host，
    /// 不该让他对着同一张错误页再点一次「重试」。
    ///
    /// 同步方法，不放 `await`：请求由 controller 自己持有，不挂在视图的 `.task` 上。
    /// 这样关闭 sheet 不会取消请求，也就没有「上一次正在收尾、本次展示被挡在骨架」的窗口。
    func loadIfNeeded() {
        guard loadTask == nil else {
            return
        }

        // 详情已明确为零条：`applyCommentCount` 已经把状态落到 `.loaded`，这里直接返回。

        switch loadState {
        case .idle, .failed:
            startReload()
        case .loading, .loaded:
            return
        }
    }

    /// 重新请求第 1 页，首屏与刷新都先回到骨架；已有请求在途时等它结束，不重复发。
    ///
    /// 刷新意味着评论整体换过一轮：保留旧列表会在新数据到达的瞬间整片替换，
    /// 反而比骨架更像「闪了一下」。
    func reload() async {
        if let loadTask {
            await loadTask.value
            return
        }

        await startReload().value
    }

    /// 启动一次第 1 页请求，返回可等待的句柄；结束时按代次清理，避免误清新任务。
    @discardableResult
    private func startReload() -> Task<Void, Never> {
        loadGeneration += 1
        let generation = loadGeneration
        let task = Task { [weak self] in
            await self?.performReload()
            guard let self, loadGeneration == generation else {
                return
            }

            loadTask = nil
        }
        loadTask = task
        return task
    }

    /// 请求第 1 页并落状态；首屏与刷新共用。
    private func performReload() async {
        guard !isLoadingMore else {
            return
        }

        loadState = .loading
        loadMoreErrorMessage = nil
        // 列表整体换过一轮，在途的回复请求结果不能再写回。
        repliesGeneration += 1
        // 骨架期间卡片不可见，展开状态一并复位，重新加载后从收起态开始。
        replies.removeAll()
        page = 0
        hasMorePages = true
        // 新的一轮列表，上一轮的分页失败记录作废。
        failedLoadMorePage = nil

        do {
            let result = try await provider.loadPage(1)
            try Task.checkCancellation()
            page = 1
            comments = result.comments
            total = result.total
            // 第一页的累计条数就是本页条数。
            hasMorePages = resolvesHasMore(
                result,
                accumulatedCount: result.comments.count,
                freshCount: result.comments.count,
            )
            loadState = .loaded
        } catch is CancellationError {
            if Task.isCancelled {
                // 请求离开视图后不再被视图取消；仍保留这条分支兜住将来的显式取消。
                loadState = .idle
            } else {
                // 来源内部取消（Host 切换、Session 重建）：按不可用展示并保留重试入口，
                // 否则会永远停在骨架。
                comments = []
                total = 0
                loadState = .failed(.unavailable)
            }
        } catch {
            comments = []
            // 标题上的总数也清掉，免得错误页上方挂着上一轮的数量。
            total = 0
            loadState = .failed(displayError(for: error))
        }
    }

    /// 追加下一页；只允许一个分页请求在途。
    func loadMoreIfNeeded() async {
        // 刷新时 `loadState` 会回到 `.loading`，这里的 guard 自然挡住并发的第 1 页请求。
        guard loadState == .loaded, hasMorePages, !isLoadingMore else {
            return
        }

        isLoadingMore = true
        loadMoreErrorMessage = nil
        defer { isLoadingMore = false }

        let next = page + 1

        do {
            let result = try await provider.loadPage(next)
            try Task.checkCancellation()
            page = next
            failedLoadMorePage = nil

            // 去重是必要的：分页边界可能把上一页最后一条再返回一次（有评论插入时页码会整体后移）。
            // 重复 ID 进入 `ForEach` 会撞身份，SwiftUI 只渲染其中一条，空出来的位置就是一条卡片高的空白。
            let existingIDs = Set(comments.map(\.id))
            let freshComments = result.comments.filter { !existingIDs.contains($0.id) }
            if freshComments.count != result.comments.count {
                AppLogger.error(
                    "评论分页返回重复条目 \(result.comments.count - freshComments.count) 条，page=\(next)",
                    category: "App.Comments",
                )
            }
            comments += freshComments
            total = max(total, result.total)
            hasMorePages = resolvesHasMore(
                result,
                accumulatedCount: comments.count,
                freshCount: freshComments.count,
            )
        } catch {
            // 分页请求现在由 controller 之外的非结构化任务触发，不会被视图取消；
            // 保留这条判断只兜住显式取消，其余（含来源内部取消）都按失败展示，
            // 否则列表会静默停在半页。
            if error is CancellationError, Task.isCancelled {
                return
            }

            // 同一页连续两次失败就不再让用户对着必然失败的重试：多半是服务端认为这一页不存在
            // （总数偏大、页码越界），继续点只会反复报同一个错。判停比无限重试诚实。
            if failedLoadMorePage == next {
                hasMorePages = false
                failedLoadMorePage = nil
                return
            }

            failedLoadMorePage = next
            loadMoreErrorMessage = displayMessage(for: error)
        }
    }

    /// 展开时加载第 1 页回复；已经加载过的评论再次调用时追加下一页。
    func loadReplies(commentID: String) async {
        guard let loadReplies = provider.loadReplies else {
            return
        }

        let current = replies[commentID] ?? ReplyState()
        guard !current.isLoading else {
            return
        }

        // 已经取完的回复不再发请求；展开后续页由 `loadMoreReplies` 触发。
        guard current.page == 0 || current.canLoadMore else {
            return
        }

        let next = current.page + 1
        await requestReplies(commentID: commentID, page: next, replacing: current.page == 0) {
            try await loadReplies(commentID, next)
        }
    }

    /// 追加某条评论的下一页回复。
    func loadMoreReplies(commentID: String) async {
        guard let loadReplies = provider.loadReplies else {
            return
        }

        let current = replies[commentID] ?? ReplyState()
        guard !current.isLoading, current.canLoadMore else {
            return
        }

        let next = current.page + 1
        await requestReplies(commentID: commentID, page: next, replacing: false) {
            try await loadReplies(commentID, next)
        }
    }

    /// 失败后重试当前等待的回复页。
    func retryReplies(commentID: String) async {
        let current = replies[commentID] ?? ReplyState()
        if current.page == 0 {
            await loadReplies(commentID: commentID)
        } else {
            await loadMoreReplies(commentID: commentID)
        }
    }

    /// 统一的回复请求收尾：在途标记、去重追加与失败文案只写这一处。
    private func requestReplies(
        commentID: String,
        page: Int,
        replacing: Bool,
        request: @Sendable () async throws -> ComicCommentPage,
    ) async {
        let generation = repliesGeneration

        var state = replies[commentID] ?? ReplyState()
        state.isLoading = true
        state.errorMessage = nil
        replies[commentID] = state

        do {
            let result = try await request()
            try Task.checkCancellation()
            // 列表已经换过一轮，这次结果属于旧列表，丢弃。
            guard generation == repliesGeneration else {
                return
            }

            var updated = replies[commentID] ?? ReplyState()
            // 回复接口同样会因新回复插入导致页码后移，跨页去重不能只做在顶级评论上。
            let existingIDs = Set(updated.comments.map(\.id))
            let freshReplies = result.comments.filter { !existingIDs.contains($0.id) }
            updated.page = page
            updated.comments = replacing ? freshReplies : updated.comments + freshReplies
            updated.hasMore = resolvesHasMore(
                result,
                accumulatedCount: updated.comments.count,
                freshCount: freshReplies.count,
            )
            updated.isLoading = false
            updated.errorMessage = nil
            replies[commentID] = updated
        } catch {
            guard generation == repliesGeneration else {
                return
            }

            var updated = replies[commentID] ?? ReplyState()
            updated.isLoading = false
            // 显式取消不写错误文案，用户回来还能再点；来源内部取消按失败展示。
            if !(error is CancellationError && Task.isCancelled) {
                updated.errorMessage = displayMessage(for: error)
            }
            replies[commentID] = updated
        }
    }

    /// 折算「这一页之后还有没有下一页」。
    ///
    /// 来源给了 `hasMore` 就照它的；为 `nil`（拿不到页码与总页数，例如禁漫 `/forum`）时
    /// 用**累计**条数与总数比较——注意不能用本页条数，那等于「每页都小于总数」，
    /// 末页也会判真、白请求一页。
    ///
    /// `freshCount == 0` 一律判停：整页都是已有条目说明服务端没真正翻页，
    /// 继续请求只会原地打转。
    private func resolvesHasMore(
        _ page: ComicCommentPage,
        accumulatedCount: Int,
        freshCount: Int,
    ) -> Bool {
        guard freshCount > 0 else {
            return false
        }

        if let hasMore = page.hasMore {
            return hasMore
        }

        // 连总数也没有：保守继续，撞到空页或整页重复时自然停下。
        guard page.total > 0 else {
            return true
        }

        return accumulatedCount < page.total
    }

    /// 来源错误转展示错误；无法归类时给通用网络提示。
    private func displayError(for error: any Error) -> SourceLoadDisplayError {
        guard let error = error as? ComicSourceError else {
            return .unavailable
        }

        return SourceLoadDisplayError(error)
    }

    /// 只要文案时的便捷版本。
    private func displayMessage(for error: any Error) -> String {
        displayError(for: error).message
    }
}

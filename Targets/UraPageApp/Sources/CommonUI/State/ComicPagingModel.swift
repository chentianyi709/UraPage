import Observation

/// 分页日志分类：只记录条数、代次与展示错误，不记录来源响应内容。
private let comicPagingLogCategory = "List.Paging"

/// 标准分页执行器：管理 query generation、首屏/追加/刷新/重试，并按完整身份增量去重。
///
/// 不包含来源参数编码、原始响应校验或 continuation 计算（由来源提供），
/// 也不承担筛选与骨架展示。由实际页面 owner 持有。
///
/// 泛型只约束条目的稳定身份（`Item.ID`）；漫画列表使用 `ComicPagingModel` 别名，
/// 需要保留来源额外字段的页面（例如禁漫搜索的 `adddate`）可以直接使用本类型。
@MainActor
@Observable
final class PagingModel<Item: Identifiable & Sendable, Query: Equatable & Sendable, Cursor: Sendable> {
    /// 请求某一页：`cursor` 为 `nil` 表示首屏，由来源决定第几页/游标并返回 continuation。
    ///
    /// 闭包在 MainActor 隔离下调用（分页器本身是 MainActor）：页面级 owner 可以在闭包里
    /// 直接读写自己的状态（例如接住首屏顺带产出的筛选菜单项），不需要额外跳转隔离。
    typealias LoadPage = @MainActor @Sendable (_ query: Query, _ cursor: Cursor?) async throws
        -> PageSlice<Item, Cursor>

    private(set) var items: [Item] = []
    private(set) var loadState: InitialLoadState<SourceLoadDisplayError> = .idle
    private(set) var isLoadingMore = false
    private(set) var canLoadMore = false
    private(set) var loadMoreError: SourceLoadDisplayError?

    @ObservationIgnored
    private let loadPage: LoadPage

    @ObservationIgnored
    private var currentQuery: Query?

    @ObservationIgnored
    private var cursor: Cursor?

    /// 跨响应去重集合；mapper 只处理同一响应内的重复。
    @ObservationIgnored
    private var seenIdentities: Set<Item.ID> = []

    @ObservationIgnored
    private var generation = 0

    @ObservationIgnored
    private var task: Task<Void, Never>?

    init(loadPage: @escaping LoadPage) {
        self.loadPage = loadPage
    }

    deinit {
        task?.cancel()
    }

    /// 页面出现或查询变化：查询变了按新查询重新加载首屏；同一查询只在尚未开始（`idle`）时开始。
    ///
    /// 已加载完成时保持现有内容与滚动位置；失败（含来源内部取消）由页面上的重试动作重新发起。
    func loadIfNeeded(query: Query) {
        if currentQuery != query {
            startInitial(query: query)
            return
        }

        guard loadState == .idle, task == nil else {
            return
        }

        startInitial(query: query)
    }

    /// 显式刷新当前查询：即使已加载完成也重新请求首屏。
    func reload(query: Query) {
        startInitial(query: query)
    }

    /// 首屏失败后重试当前 query。
    func retryInitialLoading() {
        guard let currentQuery else {
            return
        }

        startInitial(query: currentQuery)
    }

    /// 满足条件时加载下一页（追加）。追加失败后需先 `retryLoadMore`。
    func loadMoreIfNeeded() {
        guard loadState == .loaded,
              canLoadMore,
              !isLoadingMore,
              loadMoreError == nil,
              let currentQuery
        else {
            return
        }

        startAppend(query: currentQuery)
    }

    /// 重试当前追加失败页，不推进 cursor，也不清空已有内容。
    func retryLoadMore() {
        guard loadState == .loaded,
              canLoadMore,
              !isLoadingMore,
              loadMoreError != nil,
              let currentQuery
        else {
            return
        }

        startAppend(query: currentQuery)
    }

    /// 关闭体验或重置：取消在途任务并清空分页事实。
    func reset() {
        generation += 1
        task?.cancel()
        task = nil
        currentQuery = nil
        cursor = nil
        seenIdentities.removeAll()
        items = []
        loadState = .idle
        isLoadingMore = false
        canLoadMore = false
        loadMoreError = nil
    }

    private func startInitial(query: Query) {
        task?.cancel()

        generation += 1
        let operationGeneration = generation
        let loadPage = loadPage

        currentQuery = query
        cursor = nil
        seenIdentities.removeAll()
        items = []
        loadState = .loading
        isLoadingMore = false
        canLoadMore = false
        loadMoreError = nil

        task = Task { [weak self] in
            let result: Result<PageSlice<Item, Cursor>, any Error>
            do {
                let slice = try await loadPage(query, nil)
                try Task.checkCancellation()
                result = .success(slice)
            } catch {
                result = .failure(error)
            }
            self?.finishInitial(result, generation: operationGeneration)
        }
    }

    private func startAppend(query: Query) {
        guard task == nil else {
            return
        }

        let operationGeneration = generation
        let loadPage = loadPage
        let pageCursor = cursor

        isLoadingMore = true
        loadMoreError = nil

        task = Task { [weak self] in
            let result: Result<PageSlice<Item, Cursor>, any Error>
            do {
                let slice = try await loadPage(query, pageCursor)
                try Task.checkCancellation()
                result = .success(slice)
            } catch {
                result = .failure(error)
            }
            self?.finishAppend(result, generation: operationGeneration)
        }
    }

    /// 首屏收尾统一校验代次；旧任务不能清理新任务或提交结果。
    private func finishInitial(
        _ result: Result<PageSlice<Item, Cursor>, any Error>,
        generation operationGeneration: Int,
    ) {
        guard operationGeneration == generation else { return }

        task = nil
        switch result {
        case let .success(slice):
            let newCount = appendUnique(slice.items)
            updateContinuation(slice.continuation, newCount: newCount)
            loadState = .loaded

        case .failure(is CancellationError):
            // 页面销毁与旧查询取消已被 weak self／代次检查挡掉；能走到这里的是来源内部取消
            // （如 Host 切换使旧 Session 的在途请求失效）。按不可用处理并保留重试入口，
            // 否则页面会停在骨架且没有可恢复的入口。
            loadState = .failed(.unavailable)
            AppLogger.warning("首屏加载被来源取消，展示为不可用", category: comicPagingLogCategory)

        case let .failure(error):
            let displayError = SourceLoadDisplayError(error)
            loadState = .failed(displayError)
            AppLogger.warning("首屏加载失败，display=\(displayError)", category: comicPagingLogCategory)
        }
    }

    /// 追加失败或取消不清空已有内容，也不推进 cursor。
    private func finishAppend(
        _ result: Result<PageSlice<Item, Cursor>, any Error>,
        generation operationGeneration: Int,
    ) {
        guard operationGeneration == generation else { return }

        task = nil
        isLoadingMore = false
        switch result {
        case let .success(slice):
            let newCount = appendUnique(slice.items)
            updateContinuation(slice.continuation, newCount: newCount)
            loadMoreError = nil

        case .failure(is CancellationError):
            // 匹配代次的取消来自来源内部（如 Host 切换）。续载不记错误：isLoadingMore 已复位、
            // cursor 未推进，继续滚动会按同一 cursor 自动重试；记错误反而挡住自动续载。
            break

        case let .failure(error):
            let displayError = SourceLoadDisplayError(error)
            loadMoreError = displayError
            AppLogger.warning(
                "续载失败，display=\(displayError)，items=\(items.count)",
                category: comicPagingLogCategory,
            )
        }
    }

    /// 按完整 identity 增量去重并追加，返回本页新增数量。
    private func appendUnique(_ page: [Item]) -> Int {
        var newCount = 0
        for item in page where seenIdentities.insert(item.id).inserted {
            items.append(item)
            newCount += 1
        }
        return newCount
    }

    /// 依据来源 continuation 推进 cursor 与是否可继续；原始页规则由来源判断。
    private func updateContinuation(_ continuation: ComicPageContinuation<Cursor>, newCount: Int) {
        switch continuation {
        case .end:
            cursor = nil
            canLoadMore = false

        case let .next(nextCursor):
            cursor = nextCursor
            canLoadMore = true

        case let .whileMakingProgress(nextCursor, total):
            cursor = nextCursor
            canLoadMore = newCount > 0 && (total.map { items.count < $0 } ?? true)
        }
    }
}

/// 漫画列表的专用分页模型；行为与泛型实现完全一致。
typealias ComicPagingModel<Query: Equatable & Sendable, Cursor: Sendable> =
    PagingModel<ComicListItem, Query, Cursor>

// `ComicPageSlice` 与 `PageSlice<ComicListItem, Cursor>` 已是同一类型，
// 漫画列表直接使用 `PagingModel` 的主初始化器，不再保留转换用的 convenience init。

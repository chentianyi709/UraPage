import Observation

/// 哔咔首页的页面级状态：随机本子与最近更新（可续载）来自两个接口，各自独立加载。
///
/// 生命周期与其它首页／列表页一致：任务由状态 owner 持有，切 Tab（页面不可见）不取消；
/// 状态被销毁（切源替换体验）时取消在途请求。
/// **两个分区互不等待**：谁先完成谁先显示，另一个仍在加载时由分区骨架占位。
/// 整页只在两个分区都失败时才进入失败态；单个分区失败时在各自位置就地提示与重试。
@MainActor
@Observable
final class BikaHomeModel {
    /// 最近更新的分页查询：首页只有一种“新到旧、无筛选”列表。
    struct LatestQuery: Hashable, Sendable {}

    /// 随机本子的一次性加载（单批、不分页）；与最近更新各自加载。
    let randomComics: SourceValueLoadModel<[ComicListItem]>

    /// 最近更新的分页执行器；首屏、续载、重试与跨页去重都由公共实现承担。
    let recentlyUpdated: ComicPagingModel<LatestQuery, Int>

    init(services: BikaServices) {
        randomComics = SourceValueLoadModel(logCategory: "Bika.Home") {
            try await services.randomComics()
        }

        recentlyUpdated = ComicPagingModel(loadPage: { _, cursor in
            // 哔咔返回总页数，用它判断是否还有下一页；页码从 1 开始。
            let page = try await services.recentlyUpdatedComics(page: cursor ?? 1)

            return ComicPageSlice(
                items: page.items,
                continuation: .whileMakingProgress(
                    cursor: page.page + 1,
                    hasMore: page.page < page.totalPages,
                ),
            )
        })
    }

    // MARK: - 展示派生

    /// 页面首屏阶段：只用于整页骨架、整页失败与空态。
    ///
    /// 任一分区有结果就进入内容态，由内容视图按各分区自己的阶段显示内容或骨架；
    /// 两个分区都失败才整页失败（此时一个重试按钮同时重发两个请求）。
    var loadState: InitialLoadState<SourceLoadDisplayError> {
        if case let .failed(randomError) = randomComics.loadState,
           case .failed = recentlyUpdated.loadState {
            return .failed(randomError)
        }

        if isAwaitingFirstResult {
            return .loading
        }

        return .loaded
    }

    /// 两个分区都还没有结果（未开始或加载中）。
    private var isAwaitingFirstResult: Bool {
        let randomPending: Bool
        switch randomComics.loadState {
        case .idle, .loading:
            randomPending = true

        case .loaded, .failed:
            randomPending = false
        }

        let latestPending = recentlyUpdated.loadState == .idle || recentlyUpdated.loadState == .loading
        return randomPending && latestPending
    }

    /// 两个分区都加载完成且都没有内容（整页空态）。
    var isEmpty: Bool {
        guard case .loaded = randomComics.loadState, recentlyUpdated.loadState == .loaded else {
            return false
        }

        return randomComics.items.isEmpty && recentlyUpdated.items.isEmpty
    }

    // MARK: - 数据链

    /// 首次展示时请求随机本子与最近更新首页；都只请求一次（失败由页面重试）。
    func loadIfNeeded() {
        randomComics.loadIfNeeded()
        recentlyUpdated.loadIfNeeded(query: LatestQuery())
    }

    /// 失败态的重试：`SourceValueLoadModel` 与分页模型都只对失败分区重新发起请求。
    func retry() {
        randomComics.retry()

        if case .failed = recentlyUpdated.loadState {
            recentlyUpdated.reload(query: LatestQuery())
        }
    }

    /// 最近更新滚动进入预取区后追加下一页。
    func loadMoreIfNeeded() {
        recentlyUpdated.loadMoreIfNeeded()
    }

    /// 最近更新追加失败后重试同一页。
    func retryLoadMore() {
        recentlyUpdated.retryLoadMore()
    }
}

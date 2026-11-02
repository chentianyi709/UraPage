import SwiftUI

/// 公共漫画分页列表页：统一首屏骨架、空态、失败、追加与滚动行为。
///
/// 只编排“分页列表页”的展示状态；Query/Cursor、请求、文案与点击动作由来源页面提供。
/// `model` 由页面（生命周期 owner）在首次展示时创建并持有：页面重新出现时复用同一实例，
/// 保留已加载数据与滚动位置；请求在模型自身的任务里执行，因此页面离开不会取消在途请求。
/// 页面出现与查询变化都在这里按新查询驱动首屏加载（已加载完成时不重复请求）。
/// 卡片封面叠层由页面注入（页面自己的标记或进度），这里只负责把它透传给每张卡片。
struct PagedComicListView<Query: Equatable & Sendable, Cursor: Sendable, CoverOverlay: View>: View {
    /// 空态文案：标题与说明。
    let emptyTitle: String
    let emptyMessage: String

    /// 空态插图；搜索页传 `.search`，其余列表用默认空数据插图。
    var emptyIllustration: EmptyStateView.Illustration = .empty

    /// 首屏失败标题；失败详情使用模型给出的展示错误文案。
    let failureTitle: String

    /// 分页模型；由页面创建并持有，查询变化时页面也会直接用它继续加载。
    let model: ComicPagingModel<Query, Cursor>

    /// 当前查询；筛选变化与“前提菜单”的数据都会更新它。
    let query: Query

    /// 点击卡片；由页面决定 push 目标。
    let onSelect: (ComicListItem) -> Void

    /// 每张卡片封面上的叠层。
    let coverOverlay: (ComicListItem) -> CoverOverlay

    /// 不带封面叠层的列表（页面没有额外标记时）。
    init(
        emptyTitle: String,
        emptyMessage: String,
        emptyIllustration: EmptyStateView.Illustration = .empty,
        failureTitle: String,
        model: ComicPagingModel<Query, Cursor>,
        query: Query,
        onSelect: @escaping (ComicListItem) -> Void,
    ) where CoverOverlay == EmptyView {
        self.init(
            emptyTitle: emptyTitle,
            emptyMessage: emptyMessage,
            emptyIllustration: emptyIllustration,
            failureTitle: failureTitle,
            model: model,
            query: query,
            onSelect: onSelect,
            coverOverlay: { _ in EmptyView() },
        )
    }

    /// 页面自带封面叠层：叠层内容由页面决定，公共列表不认识它。
    init(
        emptyTitle: String,
        emptyMessage: String,
        emptyIllustration: EmptyStateView.Illustration = .empty,
        failureTitle: String,
        model: ComicPagingModel<Query, Cursor>,
        query: Query,
        onSelect: @escaping (ComicListItem) -> Void,
        @ContentBuilder coverOverlay: @escaping (ComicListItem) -> CoverOverlay,
    ) {
        self.emptyTitle = emptyTitle
        self.emptyMessage = emptyMessage
        self.emptyIllustration = emptyIllustration
        self.failureTitle = failureTitle
        self.model = model
        self.query = query
        self.onSelect = onSelect
        self.coverOverlay = coverOverlay
    }

    var body: some View {
        ZStack {
            Color.pageBackground.ignoresSafeArea()

            content
        }
        .onAppear { model.loadIfNeeded(query: query) }
        .onChange(of: query) { _, newQuery in
            model.loadIfNeeded(query: newQuery)
        }
    }

    // MARK: - 状态

    private var content: some View {
        InitialLoadView(
            model: model,
            initialState: { $0.loadState },
            isEmpty: { $0.items.isEmpty },
        ) {
            ComicGridSkeletonView()
        } empty: {
            EmptyStateView(title: emptyTitle, message: emptyMessage, illustration: emptyIllustration)
        } failure: { paging, error in
            LoadErrorView(title: failureTitle, message: error.message) {
                paging.retryInitialLoading()
            }
        } content: { paging in
            ComicGridContent(
                items: paging.items,
                onSelect: onSelect,
                isLoadingMore: paging.isLoadingMore,
                canLoadMore: paging.canLoadMore,
                loadMoreErrorMessage: paging.loadMoreError?.message,
                onLoadMore: { paging.loadMoreIfNeeded() },
                onRetryLoadMore: { paging.retryLoadMore() },
            ) { item, itemWidth, onSelect in
                ComicCardView(item: item, itemWidth: itemWidth, onSelect: onSelect) {
                    coverOverlay(item)
                }
            }
        }
    }
}

import SwiftUI

/// 绅士搜索页（对应旧项目 `ShenshiSearchView`）：搜索框与分页结果，版式与哔咔搜索页一致。
///
/// 绅士搜索接口没有排序与分类筛选，也没有热门搜索词，因此工具栏与推荐区都不出现：
/// 未搜索时显示搜索引导空态，提交关键词后显示结果网格。
struct ShenshiSearchView: View {
    @Environment(\.appShell) private var shell
    @Environment(\.shenshiServices) private var services
    @Environment(\.sourceDescriptor) private var descriptor
    @Environment(\.searchHistoryStore) private var historyStore

    /// 页面级状态 owner；Services 来自本源 Environment，因此首次展示时创建。
    @State private var model: ShenshiSearchModel?

    /// 本源搜索历史（与其它来源分开）。
    @State private var history: SearchHistoryViewModel?

    var body: some View {
        SourceSearchPage(
            searchText: searchTextBinding,
            onSubmit: { submitSearch() },
            onClear: { model?.clearSearch() },
            isSearching: model?.query != nil,
            // 绅士搜索没有条件菜单；工具栏槽位不能传空闭包（iOS 26 上 `EmptyView` 不是 `ToolbarContent`），用空分组占位（不渲染内容）。
            toolbar: {
                ToolbarItemGroup(placement: .topBarTrailing) {}
            },
            idle: {
                if let history, !history.queries.isEmpty {
                    SearchHistorySection(
                        queries: history.queries,
                        onSelect: runSearch,
                        onRemove: { query in Task { await history.remove(query) } },
                        onClear: { Task { await history.clear() } },
                    )
                } else {
                    EmptyStateView(
                        title: "搜索漫画",
                        message: "输入关键词后开始搜索",
                        illustration: .search,
                    )
                }
            },
            results: {
                if let model, let query = model.query {
                    PagedComicListView(
                        emptyTitle: "暂无搜索结果",
                        emptyMessage: "换个关键词试试",
                        emptyIllustration: .search,
                        failureTitle: "搜索失败",
                        model: model.paging,
                        query: query,
                        onSelect: open,
                    )
                }
            },
        )
        .task {
            prepareModelIfNeeded()
            await prepareHistoryIfNeeded()
        }
    }

    /// 提交搜索并记入本源历史。
    private func submitSearch() {
        model?.submitSearch()
        recordCurrentQuery()
    }

    /// 点历史词：填入搜索框并立即搜索。
    private func runSearch(_ query: String) {
        model?.searchText = query
        model?.submitSearch()
        recordCurrentQuery()
    }

    /// 记录刚提交的关键词（空串由 store 忽略）；提交后 `searchText` 已是整理后的关键词。
    private func recordCurrentQuery() {
        guard let history else { return }

        let query = model?.searchText ?? ""
        Task { await history.record(query) }
    }

    /// 首次展示时创建本源搜索历史并读取。
    private func prepareHistoryIfNeeded() async {
        if history == nil {
            history = SearchHistoryViewModel(store: historyStore, sourceID: descriptor.sourceID)
        }

        await history?.load()
    }

    /// 搜索框文本双向绑定：状态 owner 在首次展示时创建，因此不直接取 `$model`。
    private var searchTextBinding: Binding<String> {
        Binding(
            get: { model?.searchText ?? "" },
            set: { model?.searchText = $0 },
        )
    }

    /// 首次展示时创建页面状态 owner；切回本 Tab 复用同一实例。
    private func prepareModelIfNeeded() {
        guard model == nil else {
            return
        }

        model = ShenshiSearchModel(services: services)
    }

    /// 点结果卡片：push 本源漫画详情，跨来源转换由导航入口统一处理。
    private func open(_ item: ComicListItem) {
        shell.navigator.push(ShenshiRoute.detail(item.identity))
    }
}

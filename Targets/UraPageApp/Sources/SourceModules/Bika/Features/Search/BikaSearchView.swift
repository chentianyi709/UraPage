import Foundation
import SwiftUI

/// 哔咔搜索页（对应旧项目 Bika 搜索页）：搜索框、排序、分类筛选，以及热门搜索或分页结果。
///
/// 还没搜索时展示服务端热门搜索词（独立加载、失败可单独重试）；提交关键词后展示结果网格。
/// 排序与分类筛选都在标题栏：排序用选择菜单，筛选用独立 Sheet，改动后按当前关键词重新请求。
struct BikaSearchView: View {
    @Environment(\.appShell) private var shell
    @Environment(\.bikaServices) private var services
    @Environment(\.sourceDescriptor) private var descriptor
    @Environment(\.searchHistoryStore) private var historyStore

    /// 页面级状态 owner；Services 来自本源 Environment，因此首次展示时创建。
    @State private var model: BikaSearchModel?

    /// 本源搜索历史（与其它来源分开）。
    @State private var history: SearchHistoryViewModel?

    /// 打开筛选 Sheet 时的条件快照（与旧项目一致：用值驱动弹窗，闭包不读状态 owner）。
    @State private var filterDraft: BikaSearchFilterDraft?

    var body: some View {
        SourceSearchPage(
            searchText: searchTextBinding,
            onSubmit: { submitSearch() },
            onClear: { model?.clearSearch() },
            isSearching: model?.query != nil,
            toolbar: {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    SelectionMenu(
                        items: sortMenuItems,
                        selectedID: currentSort.requestValue,
                        defaultID: BikaComicSort.latest.requestValue,
                        isLoading: false,
                        systemImage: "line.3.horizontal.decrease",
                        accessibilityLabel: "切换搜索排序",
                        loadingAccessibilityLabel: "正在加载搜索排序",
                        onSelect: selectSort,
                    )

                    filterButton
                }
            },
            idle: {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        if let model {
                            SourceHotSearchTermsView(
                                title: "热门搜索",
                                model: model.recommendations,
                                onSelect: model.selectRecommendation,
                            )
                        }

                        if let history, !history.queries.isEmpty {
                            SearchHistoryView(
                                queries: history.queries,
                                onSelect: runSearch,
                                onRemove: { query in Task { await history.remove(query) } },
                                onClear: { Task { await history.clear() } },
                            )
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                }
                .scrollIndicators(.hidden)
            },
            results: {
                if let model, let query = model.query {
                    PagedComicListView(
                        emptyTitle: "暂无搜索结果",
                        emptyMessage: "换个关键词或筛选条件试试",
                        emptyIllustration: .search,
                        failureTitle: "搜索失败",
                        model: model.paging,
                        query: query,
                        onSelect: open,
                    )
                }
            },
        )
        .sheet(item: $filterDraft) { draft in
            BikaSearchFilterSheet(
                initialCategories: draft.categories,
                categories: draft.catalog,
                onApply: applyCategories,
            )
        }
        .task {
            prepareModelIfNeeded()
            model?.loadRecommendationsIfNeeded()
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
        model?.selectRecommendation(query)
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

    /// 分类筛选入口：有筛选时用实心圆图标与品牌色（旧项目同款状态提示）。
    private var filterButton: some View {
        Button {
            guard let model else {
                return
            }

            filterDraft = BikaSearchFilterDraft(
                categories: model.categories,
                catalog: model.categoriesCatalog,
            )
        } label: {
            Image(
                systemName: model?.hasCategoryFilter == true
                    ? "line.3.horizontal.decrease.circle.fill"
                    : "line.3.horizontal.decrease.circle",
            )
            .foregroundStyle(model?.hasCategoryFilter == true ? Color.brandPrimary : Color.textPrimary)
        }
        .tint(model?.hasCategoryFilter == true ? Color.brandPrimary : Color.textPrimary)
        .accessibilityLabel("筛选搜索分类")
        .accessibilityValue(model?.hasCategoryFilter == true ? "已限定分类" : "不限分类")
    }

    /// 把筛选草稿交回状态 owner；分类没变时 owner 自己会忽略。
    private func applyCategories(_ categories: Set<BikaComicCategory>) {
        model?.applyCategories(categories)
    }

    /// 打开筛选 Sheet 时的条件快照；`Identifiable` 只用于 `sheet(item:)` 的呈现身份。
    ///
    /// 分类目录模型一起带上，弹窗内容因此不需要捕获页面状态 owner。
    private struct BikaSearchFilterDraft: Identifiable {
        let id = UUID()
        let categories: Set<BikaComicCategory>
        let catalog: SourceValueLoadModel<[BikaComicCategory]>
    }

    /// 搜索框文本双向绑定：状态 owner 在首次展示时创建，因此不直接取 `$model`。
    private var searchTextBinding: Binding<String> {
        Binding(
            get: { model?.searchText ?? "" },
            set: { model?.searchText = $0 },
        )
    }

    /// 当前排序（状态 owner 尚未创建时用默认值）。
    private var currentSort: BikaComicSort {
        model?.sort ?? .latest
    }

    /// 把哔咔搜索排序组装为公共选择菜单的输入。
    private var sortMenuItems: [SelectionMenuItem] {
        BikaComicSort.allCases.map { sort in
            SelectionMenuItem(id: sort.requestValue, title: sort.displayTitle)
        }
    }

    /// 菜单回传的是请求值，这里换回本源排序枚举。
    private func selectSort(_ selectionID: String) {
        guard let sort = BikaComicSort.allCases.first(where: { $0.requestValue == selectionID }) else {
            return
        }

        model?.selectSort(sort)
    }

    /// 首次展示时创建页面状态 owner；切回本 Tab 复用同一实例。
    private func prepareModelIfNeeded() {
        guard model == nil else {
            return
        }

        model = BikaSearchModel(services: services)
    }

    /// 点结果卡片：push 本源漫画详情，跨来源转换由导航入口统一处理。
    private func open(_ item: ComicListItem) {
        shell.navigator.push(BikaRoute.detail(item.identity))
    }
}

import Foundation
import SwiftUI

/// 禁漫搜索页（对应旧项目 JM 搜索页）：搜索框、四个条件菜单与分页结果。
///
/// 比旧项目多出搜索类型与年月条件（旧项目只有排序）：四个条件都在工具栏菜单里，
/// 分别是排序、类型、年份、月份；任一改动都按当前关键词重新请求。
struct JMComicSearchView: View {
    @Environment(\.appShell) private var shell
    @Environment(\.jmComicServices) private var services
    @Environment(\.sourceDescriptor) private var descriptor
    @Environment(\.searchHistoryStore) private var historyStore

    /// 页面级状态 owner；Services 来自本源 Environment，因此首次展示时创建。
    @State private var model: JMComicSearchModel?

    /// 本源搜索历史（与其它来源分开）。
    @State private var history: SearchHistoryViewModel?

    var body: some View {
        SourceSearchPage(
            searchText: searchTextBinding,
            onSubmit: { submitSearch() },
            onClear: { model?.clearSearch() },
            isSearching: model.map { !$0.query.isEmpty } ?? false,
            toolbar: {
                // 搜索类型是与「搜什么」最相关的入口，单独放在最左，并用固定间距和其它条件分隔开。
                ToolbarItem(placement: .topBarTrailing) {
                    searchTypeMenu
                }

                ToolbarSpacer(.fixed, placement: .topBarTrailing)

                ToolbarItemGroup(placement: .topBarTrailing) {
                    sortMenu
                    yearMenu
                    monthMenu
                }
            },
            idle: {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        if let model {
                            SourceHotSearchTermsView(
                                title: "热门成人主题",
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
                if let model {
                    JMComicSearchResultsView(model: model)
                }
            },
        )
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

    // MARK: - 条件菜单

    /// 排序：最新／最多点阅／最多图片／最多爱心／最旧的。
    private var sortMenu: some View {
        SelectionMenu(
            items: JMComicSearchSort.allCases.map { sort in
                SelectionMenuItem(id: sort.rawValue, title: sort.displayTitle)
            },
            selectedID: currentSort.rawValue,
            defaultID: JMComicSearchSort.latest.rawValue,
            isLoading: false,
            systemImage: "line.3.horizontal.decrease",
            accessibilityLabel: "切换搜索排序",
            loadingAccessibilityLabel: "正在加载搜索排序",
            onSelect: selectSort,
        )
    }

    /// 类型：站内搜索／作品／作者／标签／角色。
    private var searchTypeMenu: some View {
        SelectionMenu(
            items: JMComicSearchType.allCases.map { type in
                SelectionMenuItem(id: type.rawValue, title: type.displayTitle)
            },
            selectedID: currentSearchType.rawValue,
            defaultID: JMComicSearchType.site.rawValue,
            isLoading: false,
            systemImage: "square.grid.2x2",
            accessibilityLabel: "切换搜索类型",
            loadingAccessibilityLabel: "正在加载搜索类型",
            onSelect: selectSearchType,
        )
    }

    /// 年份：全部年份 + 2017 年至今，最新在前。
    private var yearMenu: some View {
        SelectionMenu(
            items: [SelectionMenuItem(id: Self.unlimitedID, title: "全部年份")]
                + selectableYears.map { year in
                    SelectionMenuItem(id: String(year), title: "\(String(year)) 年")
                },
            selectedID: currentYear.map(String.init) ?? Self.unlimitedID,
            defaultID: Self.unlimitedID,
            isLoading: false,
            systemImage: "calendar",
            accessibilityLabel: "选择年份",
            loadingAccessibilityLabel: "正在加载年份",
            onSelect: selectYear,
        )
    }

    /// 月份：全部月份 + 1 至 12 月。
    private var monthMenu: some View {
        SelectionMenu(
            items: [SelectionMenuItem(id: Self.unlimitedID, title: "全部月份")]
                + JMComicSearchDateFilter.selectableMonths.map { month in
                    SelectionMenuItem(id: String(month), title: "\(month) 月")
                },
            selectedID: currentMonth.map(String.init) ?? Self.unlimitedID,
            defaultID: Self.unlimitedID,
            isLoading: false,
            systemImage: "clock",
            accessibilityLabel: "选择月份",
            loadingAccessibilityLabel: "正在加载月份",
            onSelect: selectMonth,
        )
    }

    /// 表示“全部”的菜单项取值，与真实年月取值区分开。
    private static let unlimitedID = "all"

    /// 可选年份：源码固定从 2017 年到今年。
    private var selectableYears: [Int] {
        JMComicSearchDateFilter.selectableYears(
            currentYear: Calendar.current.component(.year, from: Date()),
        )
    }

    // MARK: - 状态与动作

    /// 搜索框文本双向绑定：状态 owner 在首次展示时创建，因此不直接取 `$model`。
    private var searchTextBinding: Binding<String> {
        Binding(
            get: { model?.searchText ?? "" },
            set: { model?.searchText = $0 },
        )
    }

    private var currentSort: JMComicSearchSort {
        model?.sort ?? .latest
    }

    private var currentSearchType: JMComicSearchType {
        model?.searchType ?? .site
    }

    private var currentYear: Int? {
        model?.dateFilter?.year
    }

    private var currentMonth: Int? {
        model?.dateFilter?.month
    }

    /// 菜单回传的是取值字符串，这里换回本源枚举。
    private func selectSort(_ selectionID: String) {
        guard let sort = JMComicSearchSort.allCases.first(where: { $0.rawValue == selectionID }) else {
            return
        }

        model?.selectSort(sort)
    }

    private func selectSearchType(_ selectionID: String) {
        guard let type = JMComicSearchType.allCases.first(where: { $0.rawValue == selectionID }) else {
            return
        }

        model?.selectSearchType(type)
    }

    private func selectYear(_ selectionID: String) {
        model?.selectYear(selectionID == Self.unlimitedID ? nil : Int(selectionID))
    }

    private func selectMonth(_ selectionID: String) {
        model?.selectMonth(selectionID == Self.unlimitedID ? nil : Int(selectionID))
    }

    /// 首次展示时创建页面状态 owner；切回本 Tab 复用同一实例。
    private func prepareModelIfNeeded() {
        guard model == nil else {
            return
        }

        model = JMComicSearchModel(services: services)
    }
}

/// 搜索 Tab 与详情作者固定查询页共用结果、失败态、分页及精确作品跳转。
struct JMComicSearchResultsView: View {
    @Environment(\.appShell) private var shell

    let model: JMComicSearchModel

    /// 空态插图：搜索 Tab 用搜索插图；详情作者／标签的固定查询页仍用通用空数据插图。
    var emptyIllustration: EmptyStateView.Illustration = .search

    var body: some View {
        InitialLoadView(
            model: model,
            initialState: { $0.loadState },
            isEmpty: { $0.comics.isEmpty },
        ) {
            ComicGridSkeletonView()
        } empty: {
            EmptyStateView(
                title: "暂无搜索结果",
                message: "换个关键词或搜索条件试试",
                illustration: emptyIllustration,
            )
        } failure: { model, error in
            LoadErrorView(
                title: "搜索失败",
                message: error.message,
            ) {
                model.retry()
            }
        } content: { model in
            ComicGridContent(
                items: model.comics,
                onSelect: open,
                isLoadingMore: model.isLoadingMore,
                canLoadMore: model.canLoadMore,
                loadMoreErrorMessage: model.loadMoreError?.message,
                onLoadMore: { model.loadMoreIfNeeded() },
                onRetryLoadMore: { model.retryLoadMore() },
            )
        }
        .onAppear { openRedirectComic(model.redirectComicID) }
        .onChange(of: model.redirectComicID) { _, comicID in
            openRedirectComic(comicID)
        }
    }

    /// 消费服务端返回的精确作品：打开其详情（只在站内搜索命中作品时出现）。
    private func openRedirectComic(_ comicID: String?) {
        guard let comicID, !comicID.isEmpty else {
            return
        }

        model.consumeRedirectComicID()
        shell.navigator.push(
            JMComicRoute.detail(
                ComicIdentity(sourceID: .jm, comicID: comicID),
            ),
        )
    }

    /// 点结果卡片：push 本源漫画详情，跨来源转换由导航入口统一处理。
    private func open(_ item: ComicListItem) {
        shell.navigator.push(JMComicRoute.detail(item.identity))
    }
}

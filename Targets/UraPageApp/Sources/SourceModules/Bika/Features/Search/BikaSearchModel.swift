import Foundation
import Observation

/// 哔咔搜索页的页面级状态：搜索输入、排序、分类筛选、热门搜索与结果分页。
///
/// 热门搜索与搜索结果互不影响：推荐失败只影响推荐区，分类目录失败不阻止无分类搜索。
/// 页面首次展示时由视图创建（Services 来自本源 Environment），销毁时一并取消在途请求。
@MainActor
@Observable
final class BikaSearchModel {
    /// 搜索框文本（`.searchable` 绑定）。
    var searchText = ""

    /// 已提交的查询；`nil` 表示还没搜索，页面显示热门搜索。
    private(set) var query: BikaSearchQuery?

    /// 当前排序方式。
    private(set) var sort: BikaComicSort = .latest

    /// 当前限定的服务端分类；空集合表示不限分类。
    private(set) var categories: Set<BikaComicCategory> = []

    /// 热门搜索词。
    let recommendations: SourceValueLoadModel<[String]>

    /// 筛选弹窗使用的分类目录（按需加载，失败不阻止无分类搜索）。
    let categoriesCatalog: SourceValueLoadModel<[BikaComicCategory]>

    /// 结果分页执行器；只在提交过关键词后由列表视图驱动加载。
    let paging: ComicPagingModel<BikaSearchQuery, Int>

    /// 当前是否限定了搜索分类（筛选按钮据此显示选中态）。
    var hasCategoryFilter: Bool {
        !categories.isEmpty
    }

    init(services: BikaServices) {
        recommendations = SourceValueLoadModel(logCategory: "Bika.Search") {
            try await services.searchRecommendations()
        }
        categoriesCatalog = SourceValueLoadModel(logCategory: "Bika.Search") {
            try await services.categories()
        }

        // 服务端返回总页数，用它判断是否还有下一页；页码从 1 开始。
        paging = ComicPagingModel { query, cursor in
            let page = try await services.searchComics(
                query: query.keyword,
                sort: query.sort,
                categories: query.categories,
                page: cursor ?? 1,
            )

            return ComicPageSlice(
                items: page.items,
                continuation: .whileMakingProgress(
                    cursor: page.page + 1,
                    hasMore: page.page < page.totalPages,
                ),
            )
        }
    }

    // MARK: - 搜索

    /// 首次展示时加载热门搜索；分类目录由筛选弹窗按需加载。
    func loadRecommendationsIfNeeded() {
        recommendations.loadIfNeeded()
    }

    /// 提交搜索框里的关键词。
    func submitSearch() {
        submit(searchText)
    }

    /// 点热门搜索词：填入搜索框并立即搜索。
    func selectRecommendation(_ keyword: String) {
        searchText = keyword
        submit(keyword)
    }

    /// 清空搜索框：取消结果、回到热门搜索，保留排序与分类选择。
    func clearSearch() {
        paging.reset()
        searchText = ""
        query = nil
    }

    /// 切换排序：已搜索过就按新排序重新请求。
    func selectSort(_ sort: BikaComicSort) {
        guard sort != self.sort else {
            return
        }

        self.sort = sort
        reloadIfSearched()
    }

    /// 应用筛选弹窗里的多选分类：已搜索过就按新条件重新请求。
    func applyCategories(_ categories: Set<BikaComicCategory>) {
        guard categories != self.categories else {
            return
        }

        self.categories = categories
        reloadIfSearched()
    }

    // MARK: - 内部

    /// 整理关键词并开始搜索；关键词为空等同清空，相同查询不重发（失败态由结果区重试）。
    private func submit(_ keyword: String) {
        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            clearSearch()
            return
        }

        searchText = trimmed
        let nextQuery = makeQuery(keyword: trimmed)
        guard nextQuery != query else {
            return
        }

        query = nextQuery
    }

    /// 已搜索过时按当前排序与分类重新生成查询（列表视图据此重新加载）。
    private func reloadIfSearched() {
        guard let query else {
            return
        }

        self.query = makeQuery(keyword: query.keyword)
    }

    private func makeQuery(keyword: String) -> BikaSearchQuery {
        BikaSearchQuery(
            keyword: keyword,
            sort: sort,
            categories: orderedSelectedCategories,
        )
    }

    /// 按服务端分类顺序排列已选分类；目录未加载时保持空。
    private var orderedSelectedCategories: [BikaComicCategory] {
        categoriesCatalog.items.filter(categories.contains)
    }
}

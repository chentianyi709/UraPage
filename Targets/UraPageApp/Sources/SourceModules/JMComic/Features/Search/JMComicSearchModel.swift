import Foundation
import Observation

/// 禁漫搜索页的查询参数；作为分页模型的重载 token。
struct JMComicSearchQuery: Equatable, Sendable {
    let keyword: String
    let sort: JMComicSearchSort
    let searchType: JMComicSearchType
    let dateFilter: JMComicSearchDateFilter?
}

/// 禁漫搜索页的页面级状态：搜索输入、搜索条件、结果分页与精确作品跳转。
///
/// 分页、跨页去重、代次与取消统一交给 `PagingModel`；这里只保留搜索条件、
/// 结果排序投影与“站内搜索命中作品”的一次性跳转。`Entry` 保留 `adddate`，
/// 因此「最旧的」可以在聚合多页后按源码规则本地升序重排。
@MainActor
@Observable
final class JMComicSearchModel {
    /// 搜索框文本（`.searchable` 绑定）。
    var searchText = ""

    /// 已提交的关键词；空表示还没搜索（页面显示搜索引导空态）。
    private(set) var query = ""

    /// 搜索类型（站内搜索／作品／作者／标签／角色）。
    private(set) var searchType: JMComicSearchType = .site

    /// 年月筛选；`nil` 表示不限时间。
    private(set) var dateFilter: JMComicSearchDateFilter?

    /// 排序方式。
    private(set) var sort: JMComicSearchSort = .latest

    /// 结果分页执行器；条目保留 `adddate`，展示时再按排序投影成漫画卡片。
    let paging: PagingModel<JMComicSearchComicPage.Entry, JMComicSearchQuery, Int>

    /// 搜索页热门搜索词；独立加载，失败只影响推荐区，不影响搜索。
    let recommendations: SourceValueLoadModel<[String]>

    /// 服务端精确作品等一次性页面元数据；刷新或清空时随分页一起重置。
    @ObservationIgnored private let metadata = JMComicSearchMetadata()

    /// 当前展示的漫画（「最旧的」在聚合后本地升序；其余沿用服务端顺序）。
    var comics: [ComicListItem] {
        let entries = paging.items
        guard sort.isLocalOldest else {
            return entries.map(\.comic)
        }

        return entries
            .sorted { $0.addedAt < $1.addedAt }
            .map(\.comic)
    }

    /// 首屏阶段；直接投影分页模型。
    var loadState: InitialLoadState<SourceLoadDisplayError> {
        paging.loadState
    }

    /// 是否正在追加下一页。
    var isLoadingMore: Bool {
        paging.isLoadingMore
    }

    /// 是否还有下一页。
    var canLoadMore: Bool {
        paging.canLoadMore
    }

    /// 最近一次追加失败的展示错误。
    var loadMoreError: SourceLoadDisplayError? {
        paging.loadMoreError
    }

    /// 服务端给出的精确作品；页面消费后打开详情。
    var redirectComicID: String? {
        metadata.redirectComicID
    }

    @ObservationIgnored private let services: JMComicServices

    init(services: JMComicServices) {
        self.services = services

        recommendations = SourceValueLoadModel(logCategory: "JM.Search") {
            try await services.searchHotTags()
        }

        // 闭包在分页器初始化时建立，不能捕获 self；页面元数据先由独立盒子接住。
        let metadata = metadata
        paging = PagingModel { query, cursor in
            let requestedPage = cursor ?? 1
            let page = try await services.searchComics(
                query: query.keyword,
                sort: query.sort,
                searchType: query.searchType,
                dateFilter: query.dateFilter,
                page: requestedPage,
            )
            // 只有首屏携带「站内搜索命中作品」的跳转值；追加页不参与，避免清掉尚未消费的值。
            if cursor == nil {
                metadata.redirectComicID = page.redirectComicID
            }

            // 服务端返回总数；是否继续由“本页产生新条目”与总数共同判断。
            return PageSlice(
                items: page.entries,
                continuation: .whileMakingProgress(cursor: requestedPage + 1, total: page.total),
            )
        }
    }

    // MARK: - 搜索输入与条件

    /// 首次展示时加载热门搜索词。
    func loadRecommendationsIfNeeded() {
        recommendations.loadIfNeeded()
    }

    /// 点热门搜索词：填入搜索框并立即搜索。
    func selectRecommendation(_ keyword: String) {
        searchText = keyword
        submitSearch()
    }

    /// 提交搜索框里的关键词；相同查询不重发（失败态由结果区的重试按钮重新请求）。
    func submitSearch() {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            clearSearch()
            return
        }

        searchText = trimmed
        guard trimmed != query else {
            return
        }

        query = trimmed
        reload()
    }

    /// 清空搜索框：取消结果、回到搜索引导态；保留搜索条件。
    func clearSearch() {
        paging.reset()
        metadata.redirectComicID = nil
        searchText = ""
        query = ""
    }

    /// 切换排序：已搜索过就按新排序重新请求。
    func selectSort(_ sort: JMComicSearchSort) {
        guard sort != self.sort else {
            return
        }

        self.sort = sort
        reloadIfSearched()
    }

    /// 切换搜索类型：已搜索过就按新类型重新请求。
    func selectSearchType(_ searchType: JMComicSearchType) {
        guard searchType != self.searchType else {
            return
        }

        self.searchType = searchType
        reloadIfSearched()
    }

    /// 选择年份；`nil` 表示不限年份。
    func selectYear(_ year: Int?) {
        guard year != dateFilter?.year else {
            return
        }

        dateFilter = makeDateFilter(year: year, month: dateFilter?.month)
        reloadIfSearched()
    }

    /// 选择月份；`nil` 表示不限月份。
    func selectMonth(_ month: Int?) {
        guard month != dateFilter?.month else {
            return
        }

        dateFilter = makeDateFilter(year: dateFilter?.year, month: month)
        reloadIfSearched()
    }

    /// 首屏失败后的重试。
    func retry() {
        guard !query.isEmpty else {
            return
        }

        paging.retryInitialLoading()
    }

    // MARK: - 分页

    /// 网格进入预取区时加载下一页。
    func loadMoreIfNeeded() {
        paging.loadMoreIfNeeded()
    }

    /// 清除分页错误并重新请求相同的下一页。
    func retryLoadMore() {
        paging.retryLoadMore()
    }

    /// 清除已经交给页面处理的精确作品跳转请求。
    func consumeRedirectComicID() {
        metadata.redirectComicID = nil
    }

    // MARK: - 内部

    /// 年月都不限时为 `nil`（与不限时间等价）。
    private func makeDateFilter(year: Int?, month: Int?) -> JMComicSearchDateFilter? {
        guard year != nil || month != nil else {
            return nil
        }

        return JMComicSearchDateFilter(year: year, month: month)
    }

    /// 已搜索过时按当前条件重新请求（关键词保留）。
    private func reloadIfSearched() {
        guard !query.isEmpty else {
            return
        }

        reload()
    }

    /// 用当前关键词与条件强制重载；查询值相同也必须重新请求。
    private func reload() {
        metadata.redirectComicID = nil
        paging.reload(query: JMComicSearchQuery(
            keyword: query,
            sort: sort,
            searchType: searchType,
            dateFilter: dateFilter,
        ))
    }
}

/// 搜索页的一次性服务端元数据；由分页加载闭包写入，页面读取后消费。
///
/// 不进入分页模型：`PagingModel` 只关心条目与 continuation，精确作品跳转属于页面语义。
@MainActor
@Observable
private final class JMComicSearchMetadata {
    var redirectComicID: String?
}

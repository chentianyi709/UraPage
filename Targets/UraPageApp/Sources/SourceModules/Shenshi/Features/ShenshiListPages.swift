import Foundation

/// 绅士列表内容配置工厂：只组织本源请求、空态文案与筛选菜单。
enum ShenshiListPages {
    /// 「更新」列表的筛选条件：分类，`nil` 表示“全部”。
    struct UpdatesQuery: Hashable, Sendable {
        let categoryID: Int?
    }

    /// 「排行」列表的筛选条件：统计周期 + 分类，`nil` 表示“全部”。
    struct RankingQuery: Hashable, Sendable {
        let period: ShenshiRankingPeriod
        let categoryID: Int?
    }

    /// 首页分区标题跳转到「更新」页的筛选请求：分类 id 与菜单项 id 的换算只在这里定义。
    ///
    /// 更新页只有分类一个菜单（位置 0），因此只带这一条选择。
    static func updatesFilterRequest(categoryID: Int?, token: Int) -> SourceListFilterRequest {
        SourceListFilterRequest(
            selections: [
                SourceListFilterRequest.Selection(
                    menuID: categoryMenuID,
                    selectionID: categoryID.map(String.init) ?? allItemID,
                ),
            ],
            token: token,
        )
    }

    /// 「更新」：取指定分类最近更新的漫画，末页规则由来源给出。
    ///
    /// 分类树与列表来自同一份响应（`ShenshiLatestPage.categories`）：首屏解析时顺带产出菜单项，
    /// 菜单因此不再单独请求（列表默认取“全部”，不等待菜单）。
    static func updates(services: ShenshiServices) -> SourceListPageDescriptor<UpdatesQuery, Int> {
        SourceListPageDescriptor(
            emptyTitle: "暂无最新漫画",
            emptyMessage: "稍后再来看看",
            failureTitle: "最新漫画加载失败",
            query: UpdatesQuery(categoryID: nil),
            loadPage: { query, cursor in
                let page = try await services.latest(
                    page: cursor ?? 1,
                    categoryID: query.categoryID,
                )

                // 只有首屏带菜单项：分类树在同一份响应里，后续页忽略。
                return SourceListPageLoad(
                    slice: slice(of: page),
                    menuItems: cursor == nil ? [categoryMenuID: categoryItems(page.categories)] : [:],
                )
            },
            menus: [
                categoryMenu(
                    source: .firstPage,
                    selectedID: { query in
                        query.categoryID.map(String.init) ?? allItemID
                    },
                    makeQuery: { _, selectionID in
                        // “全部”的菜单项 id 不是数字，还原查询时自然得到 `nil`。
                        UpdatesQuery(categoryID: Int(selectionID))
                    },
                ),
            ],
        )
    }

    /// 「分类」：详情分类进入的固定分类作品列表。
    static func category(
        services: ShenshiServices,
        category: ShenshiLatestCategory,
    ) -> SourceListPageDescriptor<ShenshiLatestCategory, Int> {
        SourceListPageDescriptor(
            emptyTitle: "暂无漫画",
            emptyMessage: "该分类暂时没有可展示的作品",
            failureTitle: "分类作品加载失败",
            query: category,
            loadPage: { category, cursor in
                let page = try await services.latest(page: cursor ?? 1, categoryID: category.id)
                return slice(of: page)
            },
        )
    }

    /// 「标签」：详情标签进入的固定标签作品列表。
    static func tag(
        services: ShenshiServices,
        tag: ShenshiComicTag,
    ) -> SourceListPageDescriptor<ShenshiComicTag, Int> {
        SourceListPageDescriptor(
            emptyTitle: "暂无漫画",
            emptyMessage: "该标签暂时没有可展示的作品",
            failureTitle: "标签作品加载失败",
            query: tag,
            loadPage: { tag, cursor in
                let page = try await services.tagComics(tag: tag, page: cursor ?? 1)
                return slice(of: page)
            },
        )
    }

    /// 「发布者投稿」：详情发布者进入的投稿列表；网页游标原样传给服务。
    static func publisher(
        services: ShenshiServices,
        publisher: ShenshiComicPublisher,
    ) -> SourceListPageDescriptor<ShenshiComicPublisher, String> {
        SourceListPageDescriptor(
            emptyTitle: "暂无投稿",
            emptyMessage: "该作者暂时没有可展示的作品",
            failureTitle: "投稿列表加载失败",
            query: publisher,
            loadPage: { publisher, cursor in
                let page = try await services.publisherComics(publisher: publisher, cursor: cursor)
                return ComicPageSlice(
                    items: page.items,
                    // 网页游标若指回已加载页，不能让预取持续请求同一批作品。
                    continuation: page.nextCursor
                        .map { .whileMakingProgress(cursor: $0) } ?? .end,
                )
            },
        )
    }

    /// 「排行」：取指定周期与分类的收藏排行榜。
    ///
    /// 与更新页同形：分类树与列表来自同一份响应（`ShenshiRankingPage.categories`），
    /// 首屏解析时顺带产出分类菜单项，菜单不再单独请求；周期菜单仍是固定项。
    static func ranking(services: ShenshiServices) -> SourceListPageDescriptor<RankingQuery, Int> {
        SourceListPageDescriptor(
            emptyTitle: "暂无排行内容",
            emptyMessage: "尝试切换周期或分类",
            failureTitle: "排行榜加载失败",
            query: RankingQuery(period: .weekly, categoryID: nil),
            loadPage: { query, cursor in
                let page = try await services.ranking(
                    period: query.period,
                    categoryID: query.categoryID,
                    page: cursor ?? 1,
                )

                // 只有首屏带菜单项：分类树在同一份响应里，后续页忽略。
                return SourceListPageLoad(
                    slice: slice(of: page),
                    menuItems: cursor == nil ? [categoryMenuID: categoryItems(page.categories)] : [:],
                )
            },
            menus: [
                periodMenu(),
                categoryMenu(
                    source: .firstPage,
                    selectedID: { query in
                        query.categoryID.map(String.init) ?? allItemID
                    },
                    makeQuery: { query, selectionID in
                        RankingQuery(period: query.period, categoryID: Int(selectionID))
                    },
                ),
            ],
        )
    }

    // MARK: - 筛选菜单

    /// 周期菜单：固定选项，选中态与选中后的新查询都由本源周期枚举给出。
    private static func periodMenu() -> SourceToolbarMenu<RankingQuery> {
        SourceToolbarMenu(
            id: "period",
            systemImage: "calendar",
            accessibilityLabel: "切换排行周期",
            source: .fixed(ShenshiRankingPeriod.allCases.map { period in
                SelectionMenuItem(id: period.requestValue, title: period.title)
            }),
            selectedID: { query in
                query.period.requestValue
            },
            makeQuery: { query, selectionID in
                RankingQuery(
                    period: ShenshiRankingPeriod(requestValue: selectionID) ?? query.period,
                    categoryID: query.categoryID,
                )
            },
            loadingAccessibilityLabel: "正在加载排行周期",
            // 默认是「本周」（不是列表第一项「今日」），显式声明以便非默认时高亮。
            defaultID: ShenshiRankingPeriod.weekly.requestValue,
        )
    }

    /// 分类菜单：两级分类树的来源由调用方声明（当前两页都是“与列表同一份响应”），
    /// 顶层“全部”对应不做分类筛选。
    private static func categoryMenu<Query>(
        source: SourceToolbarMenuItems,
        selectedID: @escaping @Sendable (Query) -> String,
        makeQuery: @escaping @Sendable (Query, String) -> Query,
    ) -> SourceToolbarMenu<Query> {
        SourceToolbarMenu(
            id: categoryMenuID,
            systemImage: "square.grid.2x2",
            accessibilityLabel: "切换分类",
            source: source,
            retryAccessibilityLabel: "重新加载分类",
            selectedID: selectedID,
            makeQuery: makeQuery,
            loadingAccessibilityLabel: "正在加载分类",
        )
    }

    /// 分类菜单的稳定 id；更新页与排行页共用同一个分类菜单工厂，
    /// 首屏菜单数据与外部筛选都按它定位。
    private static let categoryMenuID = "category"

    /// 分类树对应的菜单项：顶层“全部” + 两级分类。
    private static func categoryItems(_ categories: [some ShenshiMenuCategory]) -> [SelectionMenuItem] {
        [allItem] + categories.map { categoryMenuItem($0) }
    }

    /// 顶层“全部”的菜单项 id。
    private static let allItemID = "all"

    /// 顶层“全部”：不做分类筛选。
    private static let allItem = SelectionMenuItem(id: allItemID, title: "全部")

    /// 一级分类带“全部”子项（选中即该一级分类本身），二级分类用数字 id 还原查询。
    private static func categoryMenuItem(_ category: some ShenshiMenuCategory) -> SelectionMenuItem {
        let children = category.children.isEmpty
            ? []
            : [SelectionMenuItem(id: String(category.id), title: "全部")]
            + category.children.map { child in
                SelectionMenuItem(id: String(child.id), title: child.title)
            }

        return SelectionMenuItem(
            id: String(category.id),
            title: category.title,
            children: children,
        )
    }

    // MARK: - 分页

    /// 「更新」响应的展示值与续载规则。
    static func slice(of page: ShenshiLatestPage) -> ComicPageSlice<Int> {
        slice(items: page.items, page: page.page, totalPages: page.totalPages)
    }

    /// 「标签」响应的展示值与续载规则。
    static func slice(of page: ShenshiTagComicPage) -> ComicPageSlice<Int> {
        slice(items: page.items, page: page.page, totalPages: page.totalPages)
    }

    /// 「排行」响应的展示值与续载规则。
    private static func slice(of page: ShenshiRankingPage) -> ComicPageSlice<Int> {
        slice(items: page.items, page: page.page, totalPages: page.totalPages)
    }

    /// 响应声明总页数时按总页数判断；没有总页数时按“本页是否有内容”续载。
    private static func slice(
        items: [ComicListItem],
        page: Int,
        totalPages: Int?,
    ) -> ComicPageSlice<Int> {
        // 有总页数时按页数判断；没有总数时交给分页模型按本页是否产生新条目停止。
        let hasMore = totalPages.map { page < $0 } ?? true
        return ComicPageSlice(
            items: items,
            continuation: .whileMakingProgress(cursor: page + 1, hasMore: hasMore),
        )
    }
}

/// 绅士两级分类菜单的共同形状：更新页与排行榜返回的分类树字段一致。
private protocol ShenshiMenuCategory: Sendable {
    var id: Int { get }

    var title: String { get }

    var children: [Self] { get }
}

extension ShenshiLatestCategory: ShenshiMenuCategory {}
extension ShenshiRankingCategory: ShenshiMenuCategory {}

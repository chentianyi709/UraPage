import Foundation

/// 禁漫列表内容配置工厂：只组织本源请求、空态文案与筛选菜单。
enum JMComicListPages {
    /// 「最新」列表的筛选条件；当前没有筛选，用空值表达“同一种查询”。
    struct LatestQuery: Hashable, Sendable {}

    /// 「分类」列表的筛选条件：分类选择 + 排序。
    struct CategoryQuery: Hashable, Sendable {
        let selection: JMComicCategorySelection
        let sort: JMComicSort
    }

    /// 「最新」：按页取当前最新的禁漫漫画，末页规则由来源给出。
    static func latest(services: JMComicServices) -> SourceListPageDescriptor<LatestQuery, Int> {
        SourceListPageDescriptor(
            emptyTitle: "暂无最新漫画",
            emptyMessage: "稍后再来看看",
            failureTitle: "最新漫画加载失败",
            query: LatestQuery(),
            loadPage: { _, cursor in
                try await services.latest(page: cursor ?? 0)
            },
        )
    }

    /// 「分类」页的筛选菜单 id；首页跳转的筛选请求按同一 id 定位菜单，
    /// 菜单顺序调整不会影响外部筛选。
    private static let sortMenuID = "sort"
    private static let categoryMenuID = "category"

    /// 首页分区标题跳转到「分类」页的筛选请求。
    ///
    /// 与旧版一致：排序回到菜单第一个选项（最新），分类用首页给出的 slug（直接作为菜单项 id，
    /// 单段 path）。两条选择在同一次查询变更里应用，列表只重新加载一次，分类菜单数据不重新请求。
    static func categoryFilterRequest(slug: String, token: Int) -> SourceListFilterRequest {
        // 排序重置为菜单的第一个选项（`JMComicSort` 声明顺序的第一个，即「最新」）。
        let defaultSort = JMComicSort.allCases[0]

        return SourceListFilterRequest(
            selections: [
                SourceListFilterRequest.Selection(
                    menuID: sortMenuID,
                    selectionID: defaultSort.rawValue,
                ),
                SourceListFilterRequest.Selection(
                    menuID: categoryMenuID,
                    selectionID: slug,
                ),
            ],
            token: token,
        )
    }

    /// 「分类」：按分类与排序分页取漫画。
    ///
    /// 列表数据依赖分类菜单：分类接口拿到数据后，用返回的第一个分类作为筛选参数开始请求；
    /// 分类接口失败时分类菜单位置显示重试按钮，不退回默认参数。
    static func categories(services: JMComicServices) -> SourceListPageDescriptor<CategoryQuery, Int> {
        SourceListPageDescriptor(
            emptyTitle: "暂无漫画",
            emptyMessage: "尝试切换分类或排序",
            failureTitle: "分类加载失败",
            // 列表数据依赖分类菜单，本值只用于菜单显示；菜单可用后补全为第一个分类，首页跳转的筛选由筛选请求应用。
            query: CategoryQuery(
                selection: JMComicCategorySelection(path: []),
                sort: .latest,
            ),
            loadPage: { query, cursor in
                // 禁漫分类接口页码从 1 开始；响应没有总数字段，用“本页是否有内容”判断是否继续。
                let page = cursor ?? 1
                let items = try await services.categoryComics(
                    category: query.selection,
                    sort: query.sort,
                    page: page,
                )

                return ComicPageSlice(
                    items: items,
                    continuation: .whileMakingProgress(cursor: page + 1),
                )
            },
            menus: categoryMenus(services: services),
        )
    }

    /// 「分类」页的筛选菜单；数组顺序即展示顺序，外部筛选按菜单 id 定位。
    private static func categoryMenus(services: JMComicServices) -> [SourceToolbarMenu<CategoryQuery>] {
        [
            sortMenu(),
            categoryMenu(services: services),
        ]
    }

    /// 「周刊」的筛选条件：内容类型 + 星期／完结。
    struct WeeklyQuery: Hashable, Sendable {
        let type: JMComicWeeklyContentType
        let date: JMComicWeeklyDate
    }

    /// 「周刊」：按内容类型与星期分页取周刊漫画；二级页面（首页周刊分区标题 push 进入）。
    ///
    /// 页码从 1 开始，是否还有下一页由来源按当前页条目数量给出（`hasMore`）。
    static func weekly(services: JMComicServices) -> SourceListPageDescriptor<WeeklyQuery, Int> {
        SourceListPageDescriptor(
            emptyTitle: "暂无漫画",
            emptyMessage: "尝试切换类型或星期",
            failureTitle: "周刊更新加载失败",
            query: WeeklyQuery(type: .all, date: JMComicWeeklyDate.currentWeekday),
            loadPage: { query, cursor in
                let page = cursor ?? 1
                let result = try await services.weeklyComics(
                    type: query.type,
                    date: query.date,
                    page: page,
                )

                return ComicPageSlice(
                    items: result.comics,
                    continuation: .whileMakingProgress(cursor: page + 1, hasMore: result.hasMore),
                )
            },
            menus: [
                weeklyTypeMenu(),
                weeklyDateMenu(),
            ],
        )
    }

    /// 「推广」列表的筛选条件；一个分区一种查询，因此只有分区 id。
    struct PromotionQuery: Hashable, Sendable {
        let sectionID: String
    }

    /// 「推广」：按分区分页取推广漫画；二级页面（首页推广分区标题 push 进入）。
    ///
    /// 页码从 0 开始（服务端如此），是否还有下一页由服务端总数给出。
    static func promotion(
        services: JMComicServices,
        sectionID: String,
    ) -> SourceListPageDescriptor<PromotionQuery, Int> {
        SourceListPageDescriptor(
            emptyTitle: "暂无漫画",
            emptyMessage: "稍后再来看看",
            failureTitle: "漫画列表加载失败",
            query: PromotionQuery(sectionID: sectionID),
            loadPage: { query, cursor in
                let page = cursor ?? 0
                let result = try await services.promotionComics(
                    sectionID: query.sectionID,
                    page: page,
                )

                return ComicPageSlice(
                    items: result.comics,
                    continuation: .whileMakingProgress(cursor: page + 1, total: result.total),
                )
            },
        )
    }

    // MARK: - 周刊筛选菜单

    /// 内容类型菜单：固定选项，选中态与选中后的新查询都由本源枚举给出。
    private static func weeklyTypeMenu() -> SourceToolbarMenu<WeeklyQuery> {
        SourceToolbarMenu(
            id: "weekly-type",
            systemImage: "books.vertical",
            accessibilityLabel: "切换周刊类型",
            source: .fixed(JMComicWeeklyContentType.allCases.map { type in
                SelectionMenuItem(id: type.rawValue, title: type.displayTitle)
            }),
            selectedID: { query in
                query.type.rawValue
            },
            makeQuery: { query, selectionID in
                WeeklyQuery(
                    type: JMComicWeeklyContentType(rawValue: selectionID) ?? query.type,
                    date: query.date,
                )
            },
            loadingAccessibilityLabel: "正在加载周刊类型",
        )
    }

    /// 星期／完结菜单：固定选项，选中态与选中后的新查询都由本源枚举给出。
    private static func weeklyDateMenu() -> SourceToolbarMenu<WeeklyQuery> {
        SourceToolbarMenu(
            id: "weekly-date",
            systemImage: "calendar",
            accessibilityLabel: "切换周刊日期",
            source: .fixed(JMComicWeeklyDate.allCases.map { date in
                SelectionMenuItem(id: String(date.rawValue), title: date.displayTitle)
            }),
            selectedID: { query in
                String(query.date.rawValue)
            },
            makeQuery: { query, selectionID in
                WeeklyQuery(
                    type: query.type,
                    date: JMComicWeeklyDate(rawValue: Int(selectionID) ?? query.date.rawValue) ?? query.date,
                )
            },
            loadingAccessibilityLabel: "正在加载周刊日期",
            // 默认是「当前星期」（不是列表第一项），显式声明以便非默认时高亮。
            defaultID: String(JMComicWeeklyDate.currentWeekday.rawValue),
        )
    }

    // MARK: - 筛选菜单

    /// 排序菜单：固定选项，选中态与选中后的新查询都由本源排序枚举给出。
    private static func sortMenu() -> SourceToolbarMenu<CategoryQuery> {
        SourceToolbarMenu(
            id: sortMenuID,
            systemImage: "line.3.horizontal.decrease",
            accessibilityLabel: "切换排序",
            source: .fixed(JMComicSort.allCases.map { sort in
                SelectionMenuItem(id: sort.rawValue, title: sort.displayTitle)
            }),
            selectedID: { query in
                query.sort.rawValue
            },
            makeQuery: { query, selectionID in
                CategoryQuery(
                    selection: query.selection,
                    sort: JMComicSort(rawValue: selectionID) ?? query.sort,
                )
            },
            loadingAccessibilityLabel: "正在加载排序",
        )
    }

    /// 分类菜单：递归分类树从接口获取；有子分类的节点带“全部”选项。
    private static func categoryMenu(services: JMComicServices) -> SourceToolbarMenu<CategoryQuery> {
        SourceToolbarMenu(
            id: categoryMenuID,
            systemImage: "square.grid.2x2",
            accessibilityLabel: "切换分类",
            source: .remote {
                try await services.categories().map { categoryMenuItem($0) }
            },
            makeInitialQuery: { items, query in
                // 没有首页跳转（空 path）：用服务端第一个分类补全。
                guard !query.selection.path.isEmpty else {
                    return items.first.map { firstItem in
                        CategoryQuery(
                            selection: JMComicCategorySelection(path: selectionPath(fromItemID: firstItem
                                    .id)),
                            sort: query.sort,
                        )
                    }
                }

                // 首页跳转给出的请求 slug：菜单树可用时还原成完整递归路径，让工具栏选中项正确。
                // 请求值不变（`requestSlug` 仍是同一个字符串），菜单还没数据时保持原样。
                return CategoryQuery(
                    selection: JMComicCategorySelection(
                        path: normalizedCategoryPath(
                            forRequestSlug: query.selection.requestSlug,
                            in: items,
                        ) ?? query.selection.path,
                    ),
                    sort: query.sort,
                )
            },
            retryAccessibilityLabel: "重新加载分类",
            selectedID: { query in
                categoryMenuItemID(for: query.selection.path)
            },
            makeQuery: { query, selectionID in
                CategoryQuery(
                    selection: JMComicCategorySelection(path: selectionPath(fromItemID: selectionID)),
                    sort: query.sort,
                )
            },
            loadingAccessibilityLabel: "正在加载分类",
        )
    }

    /// 递归把本源分类树转成菜单项；菜单项 id 用 `/` 连接完整 slug path（可逆）。
    private static func categoryMenuItem(
        _ category: JMComicCategory,
        parentPath: [String] = [],
    ) -> SelectionMenuItem {
        let path = parentPath + [category.slug]
        let children = category.children.isEmpty
            ? []
            : [SelectionMenuItem(id: categoryMenuItemID(for: path), title: "全部")]
            + category.children.map { categoryMenuItem($0, parentPath: path) }

        return SelectionMenuItem(
            id: categoryMenuItemID(for: path),
            title: category.name,
            children: children,
        )
    }

    /// 在分类菜单项里找请求 slug 对应的完整递归 path。
    ///
    /// 首页分区给出的 slug 是服务端请求值（各级 slug 用 `_` 连接），菜单项 id 是完整路径用 `/` 连接：
    /// 嵌套分类（如 `hanman_xxx`）用单段 path 时请求值虽然正确，但菜单项 id 不同、选中项无法高亮。
    /// 旧版 `JMComicCategorySelection.matchingHomeSectionSlug` 做的是同一件事；这里放在 `makeInitialQuery`
    /// （分类菜单数据到达时）执行，因此跳转早于菜单加载也能补上选中项。
    private static func normalizedCategoryPath(
        forRequestSlug slug: String,
        in items: [SelectionMenuItem],
    ) -> [String]? {
        for item in items {
            let path = selectionPath(fromItemID: item.id)
            if path.joined(separator: "_") == slug {
                return path
            }

            if let nestedPath = normalizedCategoryPath(forRequestSlug: slug, in: item.children) {
                return nestedPath
            }
        }

        return nil
    }

    /// 分类选择对应的菜单项 id；空 path（“全部”）对应空字符串。
    private static func categoryMenuItemID(for path: [String]) -> String {
        path.joined(separator: "/")
    }

    /// 从菜单项 id 还原分类 path；`/` 只作分隔符，slug 本身不含它。
    private static func selectionPath(fromItemID itemID: String) -> [String] {
        itemID.isEmpty ? [] : itemID.split(separator: "/").map(String.init)
    }
}

import Foundation

/// 哔咔列表内容配置工厂：只组织本源请求、空态文案与筛选菜单。
enum BikaListPages {
    /// 「分类」列表的筛选条件：分类与排序。
    ///
    /// 分类在「分类菜单」数据可用前为 `nil`，此时不会请求列表（见 `makeInitialQuery`）。
    struct CategoryQuery: Hashable, Sendable {
        let category: BikaComicCategory?
        let sort: BikaComicSort
    }

    /// 「分类」：按分类与排序分页取漫画。
    ///
    /// 列表数据依赖分类菜单：分类接口拿到数据后才默认选中第一个分类并开始请求；
    /// 分类接口失败时分类菜单位置显示重试按钮，不退回其它列表。
    static func categories(services: BikaServices) -> SourceListPageDescriptor<CategoryQuery, Int> {
        SourceListPageDescriptor(
            emptyTitle: "暂无漫画",
            emptyMessage: "尝试切换分类或排序",
            failureTitle: "分类加载失败",
            // 列表数据依赖分类菜单，本值只用于菜单显示；菜单可用后会被补全。
            query: CategoryQuery(category: nil, sort: .latest),
            loadPage: { query, cursor in
                try await filteredPage(
                    services: services,
                    filter: query.category.map(BikaComicListFilter.category),
                    sort: query.sort,
                    cursor: cursor,
                )
            },
            menus: [
                sortMenu(),
                categoryMenu(services: services),
            ],
        )
    }

    /// 「上传者作品」列表的筛选条件：固定的上传者 id。
    struct UploaderQuery: Hashable, Sendable {
        let id: String
    }

    /// 「上传者作品」：按上传者 id 分页取漫画；二级页面（从骑士榜进入）。
    ///
    /// 服务端返回总页数，用它判断是否还有下一页；排序沿用默认的“新到旧”。
    static func uploader(
        services: BikaServices,
        id: String,
        name: String,
    ) -> SourceListPageDescriptor<UploaderQuery, Int> {
        SourceListPageDescriptor(
            emptyTitle: "暂无漫画",
            emptyMessage: "稍后再来看看",
            failureTitle: "漫画列表加载失败",
            query: UploaderQuery(id: id),
            loadPage: { query, cursor in
                try await filteredPage(
                    services: services,
                    filter: .contributor(.uploader(id: query.id, name: name)),
                    sort: .latest,
                    cursor: cursor,
                )
            },
        )
    }

    /// 详情进入的固定分类／标签／贡献者及当前排序。
    struct FilteredQuery: Hashable, Sendable {
        let filter: BikaComicListFilter
        let sort: BikaComicSort
    }

    /// 三种详情筛选共用同一请求、分页和排序；来源私有的筛选值保持原样。
    static func filtered(
        services: BikaServices,
        filter: BikaComicListFilter,
    ) -> SourceListPageDescriptor<FilteredQuery, Int> {
        let emptyMessage = switch filter {
        case .category: "该分类暂时没有可展示的作品"
        case .tag: "该标签暂时没有可展示的作品"
        case .contributor(.author): "该作者暂时没有可展示的作品"
        case .contributor(.chineseTeam): "该汉化组暂时没有可展示的作品"
        case .contributor(.uploader): "该上传者暂时没有可展示的作品"
        }
        let failureTitle = switch filter {
        case .category: "分类作品加载失败"
        case .tag: "标签作品加载失败"
        case .contributor: "漫画列表加载失败"
        }

        return SourceListPageDescriptor(
            emptyTitle: "暂无漫画",
            emptyMessage: emptyMessage,
            failureTitle: failureTitle,
            query: FilteredQuery(filter: filter, sort: .latest),
            loadPage: { query, cursor in
                try await filteredPage(
                    services: services,
                    filter: query.filter,
                    sort: query.sort,
                    cursor: cursor,
                )
            },
            menus: [sortMenu(
                selectedID: { $0.sort.requestValue },
                makeQuery: { query, selectionID in
                    FilteredQuery(
                        filter: query.filter,
                        sort: BikaComicSort.allCases.first { $0.requestValue == selectionID } ?? query.sort,
                    )
                },
            )],
        )
    }

    /// 分类、上传者及详情筛选共用同一请求和续载规则；页码从 1 开始。
    private static func filteredPage(
        services: BikaServices,
        filter: BikaComicListFilter?,
        sort: BikaComicSort,
        cursor: Int?,
    ) async throws -> ComicPageSlice<Int> {
        let page = try await services.filteredComics(filter: filter, sort: sort, page: cursor ?? 1)
        return ComicPageSlice(
            items: page.items,
            continuation: .whileMakingProgress(
                cursor: page.page + 1,
                hasMore: page.page < page.totalPages,
            ),
        )
    }

    // MARK: - 筛选菜单

    /// 固定条件列表共用的排序菜单；具体查询只负责保留自身条件。
    private static func sortMenu<Query: Hashable & Sendable>(
        selectedID: @escaping @Sendable (Query) -> String,
        makeQuery: @escaping @Sendable (Query, String) -> Query,
    ) -> SourceToolbarMenu<Query> {
        SourceToolbarMenu(
            id: "sort",
            systemImage: "line.3.horizontal.decrease",
            accessibilityLabel: "切换排序",
            source: .fixed(BikaComicSort.allCases.map { sort in
                SelectionMenuItem(id: sort.requestValue, title: sort.displayTitle)
            }),
            selectedID: selectedID,
            makeQuery: makeQuery,
            loadingAccessibilityLabel: "正在加载排序",
        )
    }

    /// 排序菜单：固定选项，选中态与选中后的新查询都由本源排序枚举给出。
    private static func sortMenu() -> SourceToolbarMenu<CategoryQuery> {
        sortMenu(
            selectedID: { query in
                query.sort.requestValue
            },
            makeQuery: { query, selectionID in
                CategoryQuery(
                    category: query.category,
                    sort: BikaComicSort.allCases.first { $0.requestValue == selectionID } ?? query.sort,
                )
            },
        )
    }

    /// 分类菜单：分类列表从接口获取，并声明“分类数据是列表数据的前提”。
    private static func categoryMenu(services: BikaServices) -> SourceToolbarMenu<CategoryQuery> {
        SourceToolbarMenu(
            id: "category",
            systemImage: "square.grid.2x2",
            accessibilityLabel: "切换分类",
            source: .remote {
                try await (services.categories()).map { category in
                    SelectionMenuItem(id: category.title, title: category.title)
                }
            },
            makeInitialQuery: { items, query in
                // 分类数据是列表数据的前提：默认选中服务端返回的第一个分类。
                items.first.map { firstItem in
                    CategoryQuery(category: BikaComicCategory(title: firstItem.id), sort: query.sort)
                }
            },
            retryAccessibilityLabel: "重新加载分类",
            selectedID: { query in
                query.category?.title ?? ""
            },
            makeQuery: { query, selectionID in
                CategoryQuery(category: BikaComicCategory(title: selectionID), sort: query.sort)
            },
            loadingAccessibilityLabel: "正在加载分类",
        )
    }
}

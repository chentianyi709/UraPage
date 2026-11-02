import Foundation

/// 来源分页列表内容的配置：仅提供请求、空态文案与筛选菜单。
///
/// 所有分页漫画列表（页码或来源游标）共用一个形状：`cursor` 为 `nil` 表示首屏，
/// 末页规则由来源在 `ComicPageSlice` 里给出。
/// 筛选条件折进 `loadPage`；`query` 同时是刷新 token 与菜单选中态的来源。
struct SourceListPageDescriptor<Query: Hashable & Sendable, Cursor: Sendable>: Sendable {
    /// 空态文案（标题 + 说明）。
    let emptyTitle: String
    let emptyMessage: String

    /// 首屏失败标题。
    let failureTitle: String

    /// 初始查询；筛选变化时页面用它派生出新值。
    let query: Query

    /// 请求某一页；`cursor == nil` 表示首屏。
    ///
    /// 返回值可带上本页顺带产出的筛选菜单项（`SourceListPageLoad.menuItems`），
    /// 供声明 `.firstPage` 来源的菜单消费。
    let loadPage: @Sendable (Query, Cursor?) async throws -> SourceListPageLoad<Cursor>

    /// 右上角选择菜单（顺序即展示顺序）；空数组表示没有筛选。
    let menus: [SourceToolbarMenu<Query>]

    /// 只返回列表切片的来源用这个 init；不涉及菜单与列表的数据来源关系。
    init(
        emptyTitle: String,
        emptyMessage: String,
        failureTitle: String,
        query: Query,
        loadPage: @escaping @Sendable (Query, Cursor?) async throws -> ComicPageSlice<Cursor>,
        menus: [SourceToolbarMenu<Query>] = [],
    ) {
        self.init(
            emptyTitle: emptyTitle,
            emptyMessage: emptyMessage,
            failureTitle: failureTitle,
            query: query,
            loadPage: { query, cursor in
                try await SourceListPageLoad(slice: loadPage(query, cursor))
            },
            menus: menus,
        )
    }

    /// 菜单数据与列表数据来自同一份响应的来源用这个 init：首屏返回值里带上菜单项。
    init(
        emptyTitle: String,
        emptyMessage: String,
        failureTitle: String,
        query: Query,
        loadPage: @escaping @Sendable (Query, Cursor?) async throws -> SourceListPageLoad<Cursor>,
        menus: [SourceToolbarMenu<Query>] = [],
    ) {
        // SwiftUI identity、首屏菜单字典与外部筛选都按 id 定位；重复 id 会静默错配，
        // 因此在唯一的指定 init 里把“同页唯一”从注释提升为前置条件。
        precondition(
            Set(menus.map(\.id)).count == menus.count,
            "同一列表页的菜单 id 必须唯一：\(menus.map(\.id))",
        )

        self.emptyTitle = emptyTitle
        self.emptyMessage = emptyMessage
        self.failureTitle = failureTitle
        self.query = query
        self.loadPage = loadPage
        self.menus = menus
    }
}

/// 一页加载结果：列表切片 + 本页顺带产出的筛选菜单项（按菜单 id）。
///
/// 供「筛选菜单的数据与列表数据来自同一份响应」的来源使用：请求与解析都只做一次，
/// 菜单项随首屏一起交给页面，不再让菜单单独请求（`SourceToolbarMenuItems.firstPage`）。
struct SourceListPageLoad<Cursor: Sendable>: Sendable {
    /// 本页的列表内容与续页规则。
    let slice: ComicPageSlice<Cursor>

    /// 本页响应里可用于构建筛选菜单的数据；键是菜单 id，空表示本页没有菜单数据。
    ///
    /// 键必须是同一描述里声明为 `.firstPage` 的菜单 id；来源拼错时页面模型在 Debug 直接暴露。
    let menuItems: [String: [SelectionMenuItem]]

    init(slice: ComicPageSlice<Cursor>, menuItems: [String: [SelectionMenuItem]] = [:]) {
        self.slice = slice
        self.menuItems = menuItems
    }
}

/// 筛选菜单项的数据来源（三选一，互斥）。
///
/// 三种方式由同一个页面框架支持：固定写死（排序、周期等）、来源自己的接口、
/// 与列表数据来自同一份响应。后两种的差别只在“谁去请求”，页面消费方式一致。
enum SourceToolbarMenuItems: Sendable {
    /// 固定写死。
    case fixed([SelectionMenuItem])

    /// 由来源自己的接口获取（例如 Bika／JM 的分类树）。
    case remote(@Sendable () async throws -> [SelectionMenuItem])

    /// 由列表首屏结果提供：取 `SourceListPageLoad.menuItems` 里同 id 的项。
    case firstPage
}

/// 列表页右上角选择菜单：来源只提供展示数据与“选择 → 新查询”的映射。
///
/// 菜单项支持子菜单（分类树），选中态由当前查询推导；页面据此重新加载。
struct SourceToolbarMenu<Query: Hashable & Sendable>: Sendable {
    /// 在同一页面的菜单集合中稳定且唯一；不使用数组位置作为 SwiftUI identity。
    /// 唯一性由 `SourceListPageDescriptor` 装配时前置校验。
    let id: String
    let systemImage: String
    let accessibilityLabel: String
    let loadingAccessibilityLabel: String

    /// 菜单项的数据来源：固定 / 来源接口 / 列表首屏结果，三选一。
    ///
    /// `remote` 由页面在首次展示时加载：加载中该菜单位置显示进度；请求失败时该位置变成重试按钮，
    /// 点击重新获取（来源 Services 已在自身边界记录失败）。
    /// `firstPage` 跟随列表首屏的首次成功结果：首屏到达前显示进度；首屏失败且尚无菜单数据时
    /// 该位置变成重试按钮（重试＝重新加载首屏）；首屏成功后菜单即固定，之后切换筛选导致
    /// 列表失败也不影响菜单。首屏成功但缺少该菜单数据时同样显示重试。
    let source: SourceToolbarMenuItems

    /// 声明“该菜单的数据是列表数据的前提”：加载成功后据此补全首个查询。
    ///
    /// 返回 `nil` 表示这次结果里没有可用数据，按不可用处理（菜单位置显示重试）；
    /// 在它成功之前，页面只显示等待骨架、不请求列表，也不退回其它查询。
    /// 为 `nil` 表示列表不依赖该菜单（菜单失败只影响自己）。
    let makeInitialQuery: (@Sendable ([SelectionMenuItem], Query) -> Query?)?

    /// 数据不可用时该位置的按钮文案。
    let retryAccessibilityLabel: String

    /// 当前查询对应的选中项；`nil` 表示没有可勾选项。
    let selectedID: @Sendable (Query) -> String?

    /// 选择某个选项后的新查询。
    let makeQuery: @Sendable (Query, String) -> Query

    /// 该菜单的默认选项 id，用于工具栏「非默认高亮」；`nil` 表示默认取菜单第一项。
    ///
    /// 只有默认项不是第一项时才需要显式指定（例如周刊「星期」默认是当前星期）。
    let defaultID: String?

    /// 工具栏「非默认高亮」用的默认项：显式 `defaultID` 优先，否则取菜单第一项。
    func resolvedDefaultID(items: [SelectionMenuItem]) -> String? {
        defaultID ?? items.first?.id
    }

    init(
        id: String,
        systemImage: String,
        accessibilityLabel: String,
        source: SourceToolbarMenuItems,
        makeInitialQuery: (@Sendable ([SelectionMenuItem], Query) -> Query?)? = nil,
        retryAccessibilityLabel: String = "重新加载",
        selectedID: @escaping @Sendable (Query) -> String?,
        makeQuery: @escaping @Sendable (Query, String) -> Query,
        loadingAccessibilityLabel: String? = nil,
        defaultID: String? = nil,
    ) {
        // 列表前提菜单（`makeInitialQuery`）必须自己先拿到数据，不能等列表首屏，否则互相等待。
        if makeInitialQuery != nil, case .firstPage = source {
            preconditionFailure("菜单数据来自列表首屏时不能同时作为列表前提：首屏等菜单、菜单等首屏")
        }

        self.id = id
        self.systemImage = systemImage
        self.accessibilityLabel = accessibilityLabel
        self.loadingAccessibilityLabel = loadingAccessibilityLabel ?? accessibilityLabel
        self.source = source
        self.makeInitialQuery = makeInitialQuery
        self.retryAccessibilityLabel = retryAccessibilityLabel
        self.selectedID = selectedID
        self.makeQuery = makeQuery
        self.defaultID = defaultID
    }
}

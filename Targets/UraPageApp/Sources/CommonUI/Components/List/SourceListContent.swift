import SwiftUI

/// 来源分页列表内容：筛选菜单、加载状态与公共分页网格。
///
/// 来源页面持有 `SourceListPageModel`、决定标题和卡片跳转；这里不构造来源页面外壳。
///
/// 菜单数据来自接口时：加载中该位置显示进度，**失败时变成重试按钮**（点击重新获取）；
/// 若某个菜单声明了自己的数据是列表数据的前提（`makeInitialQuery`），在它可用之前
/// 页面只显示等待骨架、不请求列表，也不退回其它查询；该前提菜单获取失败时，
/// 正文显示与列表失败相同的失败态（复用 `failureTitle`）并可就地重试。
///
/// 页面级状态与数据链在来源页面持有的 `SourceListPageModel`：切 Tab、被二级页覆盖时页面状态仍在，
/// 链会继续跑完（回到页面即为已加载内容）；页面状态被销毁（二级页 pop、切源替换体验）时
/// 立即取消在途请求。
struct SourceListContent<Query: Hashable & Sendable, Cursor: Sendable, CoverOverlay: View>: View {
    /// 来源安装的外部筛选请求（首页分区标题跳转等）；只应用一次、相同查询不重载。
    @Environment(\.sourceListFilterRequest) private var filterRequest

    let model: SourceListPageModel<Query, Cursor>?
    let onSelect: (ComicListItem) -> Void

    /// 该列表对应的可收藏书签；`nil` 时工具栏不出现收藏按钮。
    let bookmark: Bookmark?

    /// 卡片封面叠层；来源页面自己的标记由来源注入，这里只负责透传。
    let coverOverlay: (ComicListItem) -> CoverOverlay

    /// 来源自带封面叠层的列表。
    init(
        model: SourceListPageModel<Query, Cursor>?,
        onSelect: @escaping (ComicListItem) -> Void,
        bookmark: Bookmark?,
        @ContentBuilder coverOverlay: @escaping (ComicListItem) -> CoverOverlay,
    ) {
        self.model = model
        self.onSelect = onSelect
        self.bookmark = bookmark
        self.coverOverlay = coverOverlay
    }

    var body: some View {
        if let model {
            loadedContent(model)
        } else {
            skeleton
        }
    }

    private func loadedContent(_ model: SourceListPageModel<Query, Cursor>) -> some View {
        Group {
            if model.isWaitingForPrerequisiteMenu || model.isWaitingForFilterRequest(filterRequest) {
                skeleton
            } else if let message = model.prerequisiteMenuFailureMessage {
                ZStack {
                    Color.pageBackground.ignoresSafeArea()

                    LoadErrorView(title: model.descriptor.failureTitle, message: message) {
                        model.retryPrerequisiteMenu()
                    }
                }
            } else {
                list(model)
            }
        }
        .toolbar { toolbarContent(model) }
        .onAppear {
            model.startMenuLoadingIfNeeded()
            model.applyFilterRequestIfNeeded(filterRequest)
        }
        .onChange(of: filterRequest) { _, _ in
            model.applyFilterRequestIfNeeded(filterRequest)
        }
    }

    /// 首屏骨架：等待前提菜单数据（或前提菜单失败前）时使用。
    private var skeleton: some View {
        ZStack {
            Color.pageBackground.ignoresSafeArea()

            ComicGridSkeletonView()
        }
    }

    /// 分页列表本体。
    private func list(_ model: SourceListPageModel<Query, Cursor>) -> some View {
        PagedComicListView(
            emptyTitle: model.descriptor.emptyTitle,
            emptyMessage: model.descriptor.emptyMessage,
            failureTitle: model.descriptor.failureTitle,
            model: model.paging,
            query: model.query,
            onSelect: onSelect,
            coverOverlay: coverOverlay,
        )
    }

    /// 右上角的收藏按钮与筛选菜单：收藏在左、菜单在右，**两个各自独立的圆形按钮**。
    ///
    /// 三个都试过、只有第三种能把它们分开：
    /// ① 同一个 `ToolbarItem` 里套 `HStack` —— 一个工具栏项只有一层玻璃底，两个图标被包进同一颗胶囊；
    /// ② 写成两个相邻的 `ToolbarItem` —— iOS 26 仍会把相邻的工具栏项并成同一颗玻璃胶囊；
    /// ③ 两个 `ToolbarItem` 中间插一个 `ToolbarSpacer(.fixed)` —— 系统才会给各自的圆底和一段间距。
    @ContentBuilder
    private func toolbarContent(_ model: SourceListPageModel<Query, Cursor>) -> some ToolbarContent {
        if let bookmark {
            ToolbarItem(placement: .topBarTrailing) {
                BookmarkButton(bookmark: bookmark)
            }
        }

        // 收藏与菜单之间留出间隔，两者才不会被并成一颗胶囊；只有收藏、没有菜单时不需要。
        if bookmark != nil, !model.descriptor.menus.isEmpty {
            ToolbarSpacer(.fixed, placement: .topBarTrailing)
        }

        if !model.descriptor.menus.isEmpty {
            ToolbarItemGroup(placement: .topBarTrailing) {
                ForEach(model.descriptor.menus.enumerated(), id: \.element.id) { index, menu in
                    let items = model.menuItems(at: index) ?? []

                    if model.menuFailure(at: index) != nil {
                        retryButton(for: menu, at: index, model: model)
                    } else {
                        SelectionMenu(
                            items: items,
                            selectedID: menu.selectedID(model.query),
                            // 默认项：菜单显式声明的优先，否则取第一项；据此在工具栏做「非默认高亮」。
                            defaultID: menu.resolvedDefaultID(items: items),
                            isLoading: model.isAwaitingMenuData(at: index),
                            systemImage: menu.systemImage,
                            accessibilityLabel: menu.accessibilityLabel,
                            loadingAccessibilityLabel: menu.loadingAccessibilityLabel,
                            onSelect: { selectionID in
                                model.select(selectionID: selectionID, inMenuAt: index)
                            },
                        )
                    }
                }
            }
        }
    }

    /// 菜单数据不可用时的重试按钮：点击重新获取该菜单数据。
    private func retryButton(
        for menu: SourceToolbarMenu<Query>,
        at index: Int,
        model: SourceListPageModel<Query, Cursor>,
    ) -> some View {
        Button {
            model.retryMenu(at: index)
        } label: {
            // 就是一个普通图标：不套固定方框，交给工具栏按默认尺寸排。
            Image(systemName: "arrow.clockwise")
                .foregroundStyle(Color.textPrimary)
        }
        .tint(Color.textPrimary)
        .accessibilityLabel(menu.retryAccessibilityLabel)
    }
}

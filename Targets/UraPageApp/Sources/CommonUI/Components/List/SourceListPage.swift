import SwiftUI

/// 来源列表页的标题样式：Tab 根页用大标题，二级页用内联标题。
enum SourceListTitleStyle {
    case inlineLarge
    case inline
}

/// 来源列表页的公共外壳：持有页面状态、应用标题样式并安装公共列表内容。
///
/// 来源只提供标题、描述工厂和卡片点击动作；筛选菜单、骨架、失败态与分页都由
/// `SourceListContent` / `SourceListPageModel` 承担。页面状态在首次展示时创建，
/// 切 Tab 或被二级页覆盖时保持；页面被销毁时随视图释放。
/// 卡片封面叠层由来源注入（例如禁漫的「更新」标记），外壳不认识叠层内容。
struct SourceListPage<
    Services,
    Query: Hashable & Sendable,
    Cursor: Sendable,
    CoverOverlay: View,
>: View {
    @State private var model: SourceListPageModel<Query, Cursor>?

    let services: Services
    let title: (Query?) -> String
    let titleStyle: SourceListTitleStyle
    let makeDescriptor: (Services) -> SourceListPageDescriptor<Query, Cursor>
    let onSelect: (ComicListItem) -> Void

    /// 该页面代表的可收藏书签（标签／作者／分类）；`nil` 时工具栏不出现收藏按钮。
    let bookmark: Bookmark?

    /// 每张卡片封面上的叠层。
    let coverOverlay: (ComicListItem) -> CoverOverlay

    /// 固定标题，卡片不带叠层。
    init(
        title: String,
        titleStyle: SourceListTitleStyle = .inlineLarge,
        services: Services,
        bookmark: Bookmark? = nil,
        descriptor: @escaping (Services) -> SourceListPageDescriptor<Query, Cursor>,
        onSelect: @escaping (ComicListItem) -> Void,
    ) where CoverOverlay == EmptyView {
        self.init(
            title: title,
            titleStyle: titleStyle,
            services: services,
            bookmark: bookmark,
            descriptor: descriptor,
            coverOverlay: { _ in EmptyView() },
            onSelect: onSelect,
        )
    }

    /// 固定标题，卡片封面由来源叠加自己的标记。
    init(
        title: String,
        titleStyle: SourceListTitleStyle = .inlineLarge,
        services: Services,
        bookmark: Bookmark? = nil,
        descriptor: @escaping (Services) -> SourceListPageDescriptor<Query, Cursor>,
        @ContentBuilder coverOverlay: @escaping (ComicListItem) -> CoverOverlay,
        onSelect: @escaping (ComicListItem) -> Void,
    ) {
        self.services = services
        self.title = { _ in title }
        self.titleStyle = titleStyle
        self.bookmark = bookmark
        self.coverOverlay = coverOverlay
        makeDescriptor = descriptor
        self.onSelect = onSelect
    }

    /// 依赖当前查询的标题（例如周刊日期），卡片不带叠层。
    init(
        titleStyle: SourceListTitleStyle = .inlineLarge,
        services: Services,
        bookmark: Bookmark? = nil,
        descriptor: @escaping (Services) -> SourceListPageDescriptor<Query, Cursor>,
        title: @escaping (Query?) -> String,
        onSelect: @escaping (ComicListItem) -> Void,
    ) where CoverOverlay == EmptyView {
        self.init(
            titleStyle: titleStyle,
            services: services,
            bookmark: bookmark,
            descriptor: descriptor,
            title: title,
            coverOverlay: { _ in EmptyView() },
            onSelect: onSelect,
        )
    }

    /// 依赖当前查询的标题，卡片封面由来源叠加自己的标记。
    init(
        titleStyle: SourceListTitleStyle = .inlineLarge,
        services: Services,
        bookmark: Bookmark? = nil,
        descriptor: @escaping (Services) -> SourceListPageDescriptor<Query, Cursor>,
        title: @escaping (Query?) -> String,
        @ContentBuilder coverOverlay: @escaping (ComicListItem) -> CoverOverlay,
        onSelect: @escaping (ComicListItem) -> Void,
    ) {
        self.services = services
        self.title = title
        self.titleStyle = titleStyle
        self.bookmark = bookmark
        self.coverOverlay = coverOverlay
        makeDescriptor = descriptor
        self.onSelect = onSelect
    }

    var body: some View {
        content
            .task {
                guard model == nil else {
                    return
                }

                model = SourceListPageModel(descriptor: makeDescriptor(services))
            }
    }

    @ContentBuilder
    private var content: some View {
        switch titleStyle {
        case .inlineLarge:
            SourceListContent(
                model: model,
                onSelect: onSelect,
                bookmark: bookmark,
                coverOverlay: coverOverlay,
            )
            .inlineLargeNavigationTitle(title(model?.query))

        case .inline:
            SourceListContent(
                model: model,
                onSelect: onSelect,
                bookmark: bookmark,
                coverOverlay: coverOverlay,
            )
            .navigationTitle(title(model?.query))
            .toolbarTitleDisplayMode(.inline)
        }
    }
}

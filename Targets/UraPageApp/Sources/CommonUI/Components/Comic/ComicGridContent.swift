import SwiftUI

/// 固定三列漫画网格：负责滚动容器、网格布局、分页尾部与底部预取。
///
/// 只接收页面已算好的展示状态；状态视图（骨架/空态/失败）由调用方决定。
/// 返回网格时无动画恢复导航前的滚动位置；分页页传 `onLoadMore`（此时分页尾部与重试都需要），
/// 一次性榜单（如排行榜）不传 `onLoadMore`，尾部与底部预取都不安装。
/// 卡片由调用方构建；默认使用普通 `ComicCardView`，不在网格里安装图片服务或来源展示规则。
struct ComicGridContent<Item: Identifiable, CardContent: View>: View {
    let items: [Item]
    let onSelect: ((Item) -> Void)?
    let isLoadingMore: Bool
    let canLoadMore: Bool
    let loadMoreErrorMessage: String?
    let onLoadMore: (@MainActor () -> Void)?
    let onRetryLoadMore: (@MainActor () -> Void)?
    private let cardContent: (Item, CGFloat, ((Item) -> Void)?) -> CardContent

    @State private var scrollPosition = ScrollPosition()
    @State private var scrollRestoration = ComicGridScrollRestoration()

    /// 分页页传 `onLoadMore` 与 `onRetryLoadMore`；一次性榜单不传，尾部与底部预取都不安装。
    /// `cardContent` 接收列表值、列宽和点击回调；自定义卡片应使用此回调，保证返回时恢复滚动位置。
    /// 图片环境、封面叠层与其它卡片修饰均由调用方组装，普通列表无需提供闭包。
    init(
        items: [Item],
        onSelect: ((Item) -> Void)?,
        isLoadingMore: Bool,
        canLoadMore: Bool,
        loadMoreErrorMessage: String?,
        onLoadMore: (@MainActor () -> Void)? = nil,
        onRetryLoadMore: (@MainActor () -> Void)? = nil,
        @ContentBuilder cardContent: @escaping (Item, CGFloat, ((Item) -> Void)?) -> CardContent,
    ) {
        self.items = items
        self.onSelect = onSelect
        self.isLoadingMore = isLoadingMore
        self.canLoadMore = canLoadMore
        self.loadMoreErrorMessage = loadMoreErrorMessage
        self.onLoadMore = onLoadMore
        self.onRetryLoadMore = onRetryLoadMore
        self.cardContent = cardContent
    }

    var body: some View {
        GeometryReader { proxy in
            let itemWidth = ComicGridMetrics.itemWidth(for: proxy.size.width)

            withOptionalBottomPrefetch(gridScrollView(itemWidth: itemWidth))
        }
    }

    /// 构造稳定持有滚动位置的网格滚动容器。
    private func gridScrollView(itemWidth: CGFloat) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVGrid(
                columns: ComicGridMetrics.columns(itemWidth: itemWidth),
                alignment: .center,
                spacing: ComicGridMetrics.rowSpacing,
            ) {
                ForEach(items) { item in
                    cardContent(item, itemWidth, selectionAction)
                }
            }
            .padding(.horizontal, ComicGridMetrics.horizontalPadding)
            .padding(.top, ComicGridMetrics.verticalPadding)

            if onLoadMore != nil {
                PaginationFooter(
                    isLoadingMore: isLoadingMore,
                    canLoadMore: canLoadMore,
                    loadMoreErrorMessage: loadMoreErrorMessage,
                    onRetryLoadMore: onRetryLoadMore ?? {},
                )
                .padding(.horizontal, ComicGridMetrics.horizontalPadding)
            }

            Color.clear
                .frame(height: ComicGridMetrics.verticalPadding)
        }
        .scrollPosition($scrollPosition)
        .scrollToTopButton(position: $scrollPosition)
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            max(geometry.contentOffset.y + geometry.contentInsets.top, 0)
        } action: { _, offsetY in
            scrollRestoration.currentOffsetY = offsetY
        }
        .onAppear(perform: restoreScrollPositionIfNeeded)
    }

    /// 只在页面提供点击动作时记录导航前偏移。
    private var selectionAction: ((Item) -> Void)? {
        guard let onSelect else {
            return nil
        }

        return { item in
            scrollRestoration.offsetBeforeNavigation = scrollRestoration.currentOffsetY
            onSelect(item)
        }
    }

    /// 返回网格后无动画恢复导航前的纵向偏移。
    private func restoreScrollPositionIfNeeded() {
        guard let offsetY = scrollRestoration.offsetBeforeNavigation else {
            return
        }

        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            scrollPosition.scrollTo(y: offsetY)
        }
        scrollRestoration.offsetBeforeNavigation = nil
    }

    /// 只有分页页面才安装底部预取监听；是否续载由分页模型自己守卫（已加载完则不再请求）。
    @ContentBuilder
    private func withOptionalBottomPrefetch(_ content: some View) -> some View {
        if let onLoadMore {
            content.onApproachingBottom(prefetchScreens: 1.6, action: onLoadMore)
        } else {
            content
        }
    }
}

extension ComicGridContent where Item == ComicListItem {
    /// 普通漫画列表默认使用公共漫画卡片；组合身份列表提供自己的卡片构建方式。
    init(
        items: [ComicListItem],
        onSelect: ((ComicListItem) -> Void)?,
        isLoadingMore: Bool,
        canLoadMore: Bool,
        loadMoreErrorMessage: String?,
        onLoadMore: (@MainActor () -> Void)? = nil,
        onRetryLoadMore: (@MainActor () -> Void)? = nil,
        @ContentBuilder cardContent: @escaping (
            ComicListItem,
            CGFloat,
            ((ComicListItem) -> Void)?,
        ) -> CardContent = { item, itemWidth, onSelect in
            ComicCardView(item: item, itemWidth: itemWidth, onSelect: onSelect)
        },
    ) {
        // 直接赋值而不是委托：两个 init 的标签完全一致，`self.init` 会解析回本 init。
        self.items = items
        self.onSelect = onSelect
        self.isLoadingMore = isLoadingMore
        self.canLoadMore = canLoadMore
        self.loadMoreErrorMessage = loadMoreErrorMessage
        self.onLoadMore = onLoadMore
        self.onRetryLoadMore = onRetryLoadMore
        self.cardContent = cardContent
    }
}

/// 保存网格高频偏移，不让滚动采样触发 SwiftUI View 重算。
@MainActor
private final class ComicGridScrollRestoration {
    var currentOffsetY: CGFloat = 0
    var offsetBeforeNavigation: CGFloat?
}

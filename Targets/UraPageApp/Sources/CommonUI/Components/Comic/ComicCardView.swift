import SwiftUI

/// 单个漫画卡片：封面 + 标题 + 可选副标题。
///
/// 只展示 `ComicListItem`：封面按 `ComicImageSource` 区分远程与已下载，
/// 不判断来源，也不读取 Host、Setting 或网络。点击行为由上层网格回调决定。
/// 是否显示副标题由环境里的 `\.hidesComicCardSubtitles` 决定（用户设置经 App 根注入）。
struct ComicCardView<CoverOverlay: View>: View {
    @Environment(\.hidesComicCardSubtitles) private var hidesSubtitle

    let item: ComicListItem

    /// 网格算出的卡片宽度；封面高度与骨架屏都由它推导。
    let itemWidth: CGFloat

    /// 点击卡片；为空时不安装按钮。
    let onSelect: ((ComicListItem) -> Void)?

    private let coverOverlay: CoverOverlay

    /// 叠层只覆盖封面，不参与卡片尺寸计算；可传入标记、进度或独立交互控件。
    init(
        item: ComicListItem,
        itemWidth: CGFloat,
        onSelect: ((ComicListItem) -> Void)?,
        @ContentBuilder coverOverlay: () -> CoverOverlay,
    ) {
        self.item = item
        self.itemWidth = itemWidth
        self.onSelect = onSelect
        self.coverOverlay = coverOverlay()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            cover
                // 放在封面按钮外，避免调用方的交互控件嵌套在 Button label 中。
                .overlay { coverOverlay }
                .accessibilityLabel(item.title)

            Text(item.title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.textPrimary)
                .lineLimit(showsSubtitle ? 1 : 2, reservesSpace: !showsSubtitle)
                .padding(.top, 6)

            if showsSubtitle, let subtitle = item.subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(1, reservesSpace: true)
                    .padding(.top, 4)
            }
        }
        .frame(width: itemWidth, alignment: .leading)
    }

    /// 是否显示副标题：用户选择隐藏时只显示标题，标题固定两行（与旧项目一致）。
    private var showsSubtitle: Bool {
        !hidesSubtitle && item.subtitle != nil
    }

    /// 封面容器：固定宽高比占位，阴影只挂在背景 Shape 上。
    @ContentBuilder
    private var cover: some View {
        let content = coverContent
            .clipShape(RoundedRectangle(cornerRadius: ComicGridMetrics.coverCornerRadius))
            .background {
                RoundedRectangle(cornerRadius: ComicGridMetrics.coverCornerRadius)
                    .fill(Color.surface)
                    .shadow(color: Color.cardShadow, radius: 3, x: 0, y: 2)
            }

        if let onSelect {
            Button {
                onSelect(item)
            } label: {
                content
            }
            .buttonStyle(.plain)
        } else {
            content
        }
    }

    private var coverContent: some View {
        ComicCoverView(
            source: item.cover,
            targetSize: CGSize(
                width: itemWidth,
                height: ComicGridMetrics.coverHeight(forItemWidth: itemWidth),
            ),
        )
    }
}

extension ComicCardView where CoverOverlay == EmptyView {
    /// 普通卡片无需提供叠层，保留原有点击闭包的调用方式。
    init(item: ComicListItem, itemWidth: CGFloat, onSelect: ((ComicListItem) -> Void)?) {
        self.init(item: item, itemWidth: itemWidth, onSelect: onSelect) {
            EmptyView()
        }
    }
}

/// 卡片封面的长按预览：按页面尺寸放大到接近全屏宽，便于查看封面细节。
///
/// 配合 `contextMenu(menuItems:preview:)` 使用，长按整卡时系统只放大这块封面，
/// 而不是连标题与副标题一起放大；自定义预览仍由系统提供标准浮起与放大动画。
/// 预览直接显示原图（不降采样），避免放大后发虚。
private struct ComicCardCoverPreview: View {
    /// 预览高度占页面高度的上限，给系统菜单与浮起动画留出空间。
    private static let heightRatio: CGFloat = 0.62

    /// 大图预览的圆角；大于网格封面，避免看起来像直接放大的卡片。
    private static let cornerRadius: CGFloat = 12

    let item: ComicListItem
    let containerSize: CGSize

    var body: some View {
        let size = Self.previewSize(for: containerSize)

        ComicCoverView(source: item.cover, targetSize: size, downsamples: false)
            .frame(width: size.width, height: size.height)
            .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius))
            .background {
                RoundedRectangle(cornerRadius: Self.cornerRadius)
                    .fill(Color.surface)
                    .shadow(color: Color.cardShadow, radius: 12, x: 0, y: 6)
            }
            .accessibilityLabel(item.title)
    }

    /// 按封面 3:4 比例，在宽度与高度约束内取最大显示尺寸。
    private static func previewSize(for containerSize: CGSize) -> CGSize {
        let height = min(containerSize.width * 4 / 3, containerSize.height * heightRatio)
        return CGSize(width: height * 3 / 4, height: height)
    }
}

/// 漫画卡片长按菜单：在 `contextMenu` 的独立预览环境中重建封面所需的图片依赖。
///
/// 自定义 preview 不继承页面的自定义 Environment。这里一次性读取卡片当前的浏览图片
/// 作用域／服务、下载资产环境与 `displayScale`，安装到预览子树；调用方只提供菜单项，
/// 不再在每个使用处重复写一长串 `.environment(...)`。历史卡片来源特定的图片服务由
/// 卡片的 `.environment(\.browsingImageServiceStorage, …)` 提供，修饰符需位于该注入内层。
private struct ComicCardContextMenuModifier<MenuItems: View>: ViewModifier {
    @Environment(\.browsingImageScopeStorage) private var browsingImageScope: BrowsingImageScope?
    @Environment(\.browsingImageServiceStorage) private var browsingImageService: (any ComicImageService)?
    @Environment(\.downloadAssetStoreStorage) private var downloadAssetStore: DownloadAssetStore?
    @Environment(\.imageMemoryPoolStorage) private var imageMemoryPool: ImageMemoryPool?
    @Environment(\.displayScale) private var displayScale

    let item: ComicListItem
    let containerSize: CGSize
    let menuItems: () -> MenuItems

    init(
        item: ComicListItem,
        containerSize: CGSize,
        @ViewBuilder menuItems: @escaping () -> MenuItems,
    ) {
        self.item = item
        self.containerSize = containerSize
        self.menuItems = menuItems
    }

    func body(content: Content) -> some View {
        content.contextMenu(menuItems: menuItems) {
            ComicCardCoverPreview(item: item, containerSize: containerSize)
                .environment(\.browsingImageScopeStorage, browsingImageScope)
                .environment(\.browsingImageServiceStorage, browsingImageService)
                .environment(\.downloadAssetStoreStorage, downloadAssetStore)
                .environment(\.imageMemoryPoolStorage, imageMemoryPool)
                .environment(\.displayScale, displayScale)
        }
    }
}

extension View {
    /// 给漫画卡片安装长按菜单，并自动为封面预览重建图片环境。
    func comicCardContextMenu(
        item: ComicListItem,
        containerSize: CGSize,
        @ViewBuilder menuItems: @escaping () -> some View,
    ) -> some View {
        modifier(ComicCardContextMenuModifier(
            item: item,
            containerSize: containerSize,
            menuItems: menuItems,
        ))
    }
}

import SwiftUI

/// 两行横向滚动的漫画卡片分区：分区标题 + 可横向滑动的两行卡片。
///
/// 首页的「随机本子／随机推荐」这类单批内容共用；标题可自定义，默认标题没有跳转语义、
/// 固定不显示箭头。内容为空时保留标题并显示调用方给的提示（没有提示则不占内容高度），
/// 避免整块消失造成布局跳动。
/// 封面叠层由调用方注入（与 `ComicCardView` 一致）：分区只负责排版，不认识叠层内容。
struct ComicShelfSection<Header: View, CoverOverlay: View>: View {
    let items: [ComicListItem]

    /// 没有内容时显示的轻量提示；`nil` 时不显示空态。
    let emptyText: String?

    let onSelectComic: (ComicListItem) -> Void

    private let header: Header

    /// 每张卡片封面上的叠层；默认什么都不画。
    private let coverOverlay: (ComicListItem) -> CoverOverlay

    /// 两行网格按动态字号保留封面与文字高度。
    @ScaledMetric(relativeTo: .footnote)
    private var cardTextHeight: CGFloat = 44

    private var cardWidth: CGFloat {
        ComicGridMetrics.shelfCardWidth
    }

    private var cardHeight: CGFloat {
        ComicGridMetrics.coverHeight(forItemWidth: cardWidth) + cardTextHeight
    }

    /// 无跳转语义的标题分区（首页随机推荐等），卡片不带叠层。
    init(
        title: String,
        items: [ComicListItem],
        emptyText: String?,
        onSelectComic: @escaping (ComicListItem) -> Void,
    ) where Header == ComicSectionHeader, CoverOverlay == EmptyView {
        self.init(
            items: items,
            emptyText: emptyText,
            onSelectComic: onSelectComic,
            coverOverlay: { _ in EmptyView() },
        ) {
            ComicSectionHeader(title: title, showsDisclosureIndicator: false)
        }
    }

    /// 无跳转语义的标题分区，卡片封面由调用方叠加自己的标记。
    init(
        title: String,
        items: [ComicListItem],
        emptyText: String?,
        onSelectComic: @escaping (ComicListItem) -> Void,
        @ContentBuilder coverOverlay: @escaping (ComicListItem) -> CoverOverlay,
    ) where Header == ComicSectionHeader {
        self.init(
            items: items,
            emptyText: emptyText,
            onSelectComic: onSelectComic,
            coverOverlay: coverOverlay,
        ) {
            ComicSectionHeader(title: title, showsDisclosureIndicator: false)
        }
    }

    /// 自定义标题分区（如禁漫推广分区：标题可点跳转），卡片封面由调用方叠加自己的标记。
    init(
        items: [ComicListItem],
        emptyText: String?,
        onSelectComic: @escaping (ComicListItem) -> Void,
        @ContentBuilder coverOverlay: @escaping (ComicListItem) -> CoverOverlay,
        @ContentBuilder header: () -> Header,
    ) {
        self.items = items
        self.emptyText = emptyText
        self.onSelectComic = onSelectComic
        self.coverOverlay = coverOverlay
        self.header = header()
    }

    var body: some View {
        ComicSection {
            header
        } content: {
            if items.isEmpty {
                if let emptyText {
                    ComicSectionEmptyText(text: emptyText)
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHGrid(
                        rows: [
                            GridItem(
                                .fixed(cardHeight),
                                spacing: ComicGridMetrics.rowSpacing,
                                alignment: .top,
                            ),
                            GridItem(.fixed(cardHeight), alignment: .top),
                        ],
                        spacing: ComicGridMetrics.gridSpacing,
                    ) {
                        ForEach(items) { comic in
                            ComicCardView(
                                item: comic,
                                itemWidth: cardWidth,
                                onSelect: onSelectComic,
                            ) {
                                coverOverlay(comic)
                            }
                            .frame(height: cardHeight, alignment: .top)
                        }
                    }
                    .padding(.horizontal, ComicGridMetrics.horizontalPadding)
                }
                .frame(height: cardHeight * 2 + ComicGridMetrics.rowSpacing)
                .scrollClipDisabled()
            }
        }
    }
}

/// 分区没有内容时的轻量提示：保留分区标题下的占位高度，避免整块消失造成布局跳动。
struct ComicSectionEmptyText: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(Color.textTertiary)
            .frame(maxWidth: .infinity, minHeight: 72)
            .padding(.horizontal, ComicGridMetrics.horizontalPadding)
    }
}

/// 两行横向卡片分区的骨架：分区标题占位 ＋ 两行卡片占位，与 `ComicShelfSection` 同形。
///
/// 自带呼吸效果；整页骨架与「分区各自加载」时的局部骨架共用。
struct ComicShelfSkeletonSection: View {
    /// 分区标题右侧是否显示箭头占位（没有跳转语义的分区不显示）。
    let showsDisclosureIndicator: Bool

    /// 与真实卡片一致：按动态字号保留文字高度，避免大字号下骨架与内容高度不一致。
    @ScaledMetric(relativeTo: .footnote)
    private var cardTextHeight: CGFloat = 44

    private let cardCount = 8

    private var cardWidth: CGFloat {
        ComicGridMetrics.shelfCardWidth
    }

    private var cardHeight: CGFloat {
        ComicGridMetrics.coverHeight(forItemWidth: cardWidth) + cardTextHeight
    }

    var body: some View {
        ComicSectionSkeleton(showsDisclosureIndicator: showsDisclosureIndicator) {
            ComicCardSkeletonRowsView(
                cardWidth: cardWidth,
                cardCount: cardCount,
                rowSpacing: ComicGridMetrics.rowSpacing,
                cardHeight: cardHeight,
            )
        }
        .skeletonLoadingEffect()
    }
}

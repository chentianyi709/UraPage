import SwiftUI

/// 两行横向卡片占位：与真实分区同卡片宽度与行距，自带水平内边距并禁用滚动。
///
/// 只负责占位布局；卡片宽度与固定高度由调用方给出，保持与真实分区一致（含动态字号差异）。
struct ComicCardSkeletonRowsView: View {
    /// 与真实卡片一致的宽度。
    let cardWidth: CGFloat

    /// 占位卡片数量（两行交替排布）。
    let cardCount: Int

    /// 两行之间的间距。
    let rowSpacing: CGFloat

    /// 单张占位卡片的固定高度。
    let cardHeight: CGFloat

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHGrid(
                rows: [
                    GridItem(.fixed(cardHeight), spacing: rowSpacing, alignment: .top),
                    GridItem(.fixed(cardHeight), alignment: .top),
                ],
                spacing: ComicGridMetrics.gridSpacing,
            ) {
                ForEach(0 ..< cardCount, id: \.self) { _ in
                    ComicCardSkeletonView(itemWidth: cardWidth)
                        .frame(height: cardHeight, alignment: .top)
                }
            }
            .padding(.horizontal, ComicGridMetrics.horizontalPadding)
        }
        .frame(height: cardHeight * 2 + rowSpacing)
        .scrollDisabled(true)
        .scrollClipDisabled()
    }
}

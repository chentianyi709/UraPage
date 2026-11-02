import SwiftUI

/// 固定三列卡片占位网格：与真实网格同列宽、同间距，并自带水平内边距。
///
/// 只负责占位布局；纵向留白、滚动容器与呼吸动画由调用方决定。
struct ComicCardSkeletonGridView: View {
    /// 与真实卡片一致的列宽（用 `ComicGridMetrics.itemWidth(for:)` 从容器宽度算出）。
    let itemWidth: CGFloat

    /// 占位卡片数量。
    let cardCount: Int

    var body: some View {
        LazyVGrid(
            columns: ComicGridMetrics.columns(itemWidth: itemWidth),
            alignment: .center,
            spacing: ComicGridMetrics.rowSpacing,
        ) {
            ForEach(0 ..< cardCount, id: \.self) { _ in
                ComicCardSkeletonView(itemWidth: itemWidth)
            }
        }
        .padding(.horizontal, ComicGridMetrics.horizontalPadding)
    }
}

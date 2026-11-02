import SwiftUI

/// 不带滚动容器的三列漫画卡片网格；所有卡片一起参与父容器的布局动画。
///
/// 调用方决定分区标题、空态和容器宽度；长列表应使用惰性的 `ComicGridContent`。
struct ComicEagerGrid: View {
    let comics: [ComicListItem]
    let itemWidth: CGFloat
    let onSelect: (ComicListItem) -> Void

    var body: some View {
        Grid(
            alignment: .leading,
            horizontalSpacing: ComicGridMetrics.gridSpacing,
            verticalSpacing: ComicGridMetrics.rowSpacing,
        ) {
            ForEach(rowStartIndices, id: \.self) { startIndex in
                let endIndex = min(startIndex + ComicGridMetrics.columnCount, comics.endIndex)

                GridRow {
                    ForEach(comics[startIndex ..< endIndex]) { comic in
                        ComicCardView(item: comic, itemWidth: itemWidth, onSelect: onSelect)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var rowStartIndices: [Int] {
        Array(stride(from: comics.startIndex, to: comics.endIndex, by: ComicGridMetrics.columnCount))
    }
}

import SwiftUI

/// 使用与真实网格一致的三列布局展示首屏加载占位内容。
struct ComicGridSkeletonView: View {
    private let placeholderCount = 12

    var body: some View {
        GeometryReader { proxy in
            ComicCardSkeletonGridView(
                itemWidth: ComicGridMetrics.itemWidth(for: proxy.size.width),
                cardCount: placeholderCount,
            )
            .padding(.vertical, ComicGridMetrics.verticalPadding)
            .frame(maxHeight: .infinity, alignment: .top)
            .clipped()
        }
        .skeletonLoadingEffect()
    }
}

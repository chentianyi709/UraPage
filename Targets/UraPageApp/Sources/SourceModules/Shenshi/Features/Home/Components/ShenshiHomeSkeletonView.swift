import SwiftUI

/// 绅士推荐首页的骨架屏：与真实页面一致的三段「分区标题 + 六张卡片」。
struct ShenshiHomeSkeletonView: View {
    private let sectionCount = 3
    private let cardCount = 6

    var body: some View {
        GeometryReader { proxy in
            let itemWidth = ComicGridMetrics.itemWidth(for: proxy.size.width)

            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 24) {
                    ForEach(0 ..< sectionCount, id: \.self) { _ in
                        ComicSectionSkeleton {
                            ComicCardSkeletonGridView(itemWidth: itemWidth, cardCount: cardCount)
                        }
                    }
                }
                .padding(.vertical, ComicGridMetrics.verticalPadding)
            }
            .scrollDisabled(true)
        }
        .skeletonLoadingEffect()
    }
}

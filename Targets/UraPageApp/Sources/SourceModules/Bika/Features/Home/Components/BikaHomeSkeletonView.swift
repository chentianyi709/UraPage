import SwiftUI

/// 哔咔首页骨架：两行随机卡片 + 三列最近更新卡片，布局与真实内容一致。
///
/// 每段骨架各自带呼吸效果，与「分区各自加载」时的局部骨架完全同形。
struct BikaHomeSkeletonView: View {
    private let recentlyUpdatedCardCount = 9

    var body: some View {
        GeometryReader { proxy in
            let itemWidth = ComicGridMetrics.itemWidth(for: proxy.size.width)

            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 24) {
                    ComicShelfSkeletonSection(showsDisclosureIndicator: false)

                    ComicSectionSkeleton(showsDisclosureIndicator: false) {
                        ComicCardSkeletonGridView(
                            itemWidth: itemWidth,
                            cardCount: recentlyUpdatedCardCount,
                        )
                    }
                    .skeletonLoadingEffect()
                }
                .padding(.vertical, ComicGridMetrics.verticalPadding)
            }
            .scrollDisabled(true)
        }
    }
}

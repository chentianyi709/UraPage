import SwiftUI

/// 禁漫首页整页骨架：与真实页面一致的分段「分区标题 + 两行横向卡片」。
///
/// 首段对应顶部的随机推荐分区，标题右侧没有跳转箭头，占位也不显示；
/// 其余分段对应推广分区，保留箭头占位。
struct JMComicHomeSkeletonView: View {
    private let sectionCount = 4

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 24) {
                ForEach(0 ..< sectionCount, id: \.self) { index in
                    ComicShelfSkeletonSection(showsDisclosureIndicator: index > 0)
                }
            }
            .padding(.vertical, ComicGridMetrics.verticalPadding)
        }
        .scrollDisabled(true)
    }
}

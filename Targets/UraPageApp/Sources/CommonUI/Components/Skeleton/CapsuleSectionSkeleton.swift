import SwiftUI

/// 胶囊内容分区的加载骨架：标题占位 + 胶囊流占位，与 `CapsuleSection` 同一套标题块尺寸与间距。
///
/// 书签页与搜索页引导区共用，避免两处骨架的标题块、占位词与呼吸效果各写一套；
/// 自带 `skeletonLoadingEffect`，调用方只负责外层滚动与内边距。
/// 标题宽度与占位词可覆盖：书签分组标题只有两个字、内容通常三五条，
/// 直接用热门搜索的十七个词会把骨架撑成三行、比真实内容高出一截。
struct CapsuleSectionSkeleton: View {
    /// 标题占位宽度。
    var titleWidth: CGFloat = 76

    /// 胶囊占位词（只决定每块的宽度，不显示文字）。
    var placeholderTitles: [String] = CapsuleSkeletonFlow.defaultPlaceholderTitles

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SkeletonBlock(width: titleWidth, height: 20, cornerRadius: 5)

            CapsuleSkeletonFlow(placeholderTitles: placeholderTitles)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .skeletonLoadingEffect()
    }
}

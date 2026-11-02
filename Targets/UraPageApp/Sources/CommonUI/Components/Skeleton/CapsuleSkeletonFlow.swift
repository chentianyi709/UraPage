import SwiftUI

/// 胶囊列表的加载骨架：流式排布的胶囊占位，供热门搜索、筛选分类等胶囊列表共用。
///
/// 占位词只用于产生不同宽度的胶囊块，不渲染文字、对无障碍隐藏；
/// 尺寸参数由调用方按真实胶囊给出，避免首屏形态跳变；`skeletonLoadingEffect` 由调用方套在整块上。
struct CapsuleSkeletonFlow: View {
    /// 占位词（仅决定每块宽度，不显示）。
    var placeholderTitles: [String] = Self.defaultPlaceholderTitles

    /// 与真实胶囊一致的横向内边距。
    var horizontalPadding: CGFloat = 12

    /// 与真实胶囊一致的纵向内边距。
    var verticalPadding: CGFloat = 7

    /// 与真实胶囊一致的文字样式。
    var font: Font = .caption

    var body: some View {
        WrappingFlowLayout(
            horizontalSpacing: 8,
            verticalSpacing: 8,
        ) {
            ForEach(placeholderTitles, id: \.self) { title in
                Text(title)
                    .font(font)
                    .foregroundStyle(.clear)
                    .padding(.horizontal, horizontalPadding)
                    .padding(.vertical, verticalPadding)
                    .background(Color.textTertiary.opacity(0.18), in: Capsule())
            }
        }
        .accessibilityHidden(true)
    }

    /// 一组长短不一的占位词，宽度分布接近真实胶囊；长度按热门搜索骨架收成三行排布。
    static let defaultPlaceholderTitles = [
        "AI作畫",
        "蘿莉",
        "開大車",
        "3D",
        "人妻",
        "群交",
        "絕區零",
        "調教",
        "巨乳",
        "正太",
        "蔚藍檔案",
        "懷孕",
        "Cuntboy",
        "東方",
        "長篇",
        "同人",
        "短篇",
    ]
}

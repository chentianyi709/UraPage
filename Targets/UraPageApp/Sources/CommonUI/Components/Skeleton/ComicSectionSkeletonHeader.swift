import SwiftUI

/// 分区标题的骨架占位：标题块 + 尾部箭头块，高度对齐可点标题的 44pt 行高。
///
/// 与真实 `ComicSectionHeader` 同形，因此加载中的纵向节奏与加载后一致；
/// 没有跳转语义的分区骨架同样可隐藏箭头。
struct ComicSectionSkeletonHeader: View {
    let showsDisclosureIndicator: Bool

    init(showsDisclosureIndicator: Bool = true) {
        self.showsDisclosureIndicator = showsDisclosureIndicator
    }

    var body: some View {
        HStack(spacing: 8) {
            SkeletonBlock(width: 136, height: 22, cornerRadius: 6)

            Spacer()

            if showsDisclosureIndicator {
                SkeletonBlock(width: 14, height: 14, cornerRadius: 4)
            }
        }
        .frame(minHeight: ComicGridMetrics.sectionHeaderHeight)
    }
}

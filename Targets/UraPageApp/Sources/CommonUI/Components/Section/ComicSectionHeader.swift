import SwiftUI

/// 漫画内容分区的统一容器：标题行 + 内容。
///
/// 所有来源的首页分区都走这里，保证两件事一致：
/// 标题行固定 44pt 高（可点标题有足够命中区，且与骨架占位同高），
/// 「标题 → 内容」间距固定为 `ComicGridMetrics.sectionSpacing`。
/// 内容自带水平内边距（网格与横滑卡片都自带），这里只处理标题行。
struct ComicSection<Header: View, Content: View>: View {
    @ContentBuilder let header: () -> Header
    @ContentBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: ComicGridMetrics.sectionSpacing) {
            header()
                .padding(.horizontal, ComicGridMetrics.horizontalPadding)

            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 漫画内容分区共用的标题：标题文案 + 可选跳转箭头。
///
/// 只负责单行展示；是否可点、点击做什么由来源页面决定（可点标题用 `ComicSectionHeaderButton`）。
/// 没有跳转语义的分区应显式隐藏箭头，避免暗示不可用的跳转。
struct ComicSectionHeader: View {
    let title: String
    let showsDisclosureIndicator: Bool

    init(title: String, showsDisclosureIndicator: Bool = true) {
        self.title = title
        self.showsDisclosureIndicator = showsDisclosureIndicator
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.textPrimary)

            Spacer()

            if showsDisclosureIndicator {
                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: ComicGridMetrics.sectionHeaderHeight)
    }
}

/// 带跳转语义的分区标题：整行可点 + 无障碍提示，外形与高度与 `ComicSectionHeader` 一致。
struct ComicSectionHeaderButton: View {
    let title: String
    let accessibilityHint: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ComicSectionHeader(title: title)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityHint(accessibilityHint)
    }
}

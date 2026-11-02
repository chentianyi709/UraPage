import SwiftUI

/// 胶囊内容分区的统一版式：标题 + 可选整段清除入口 + 胶囊内容。
///
/// 书签页与搜索页引导区（热门搜索、最近搜索）共用，保证标题字号、「标题 → 胶囊」间距
/// 与清除入口一致。清除按钮保持 44×44 命中区，但通过 overlay 不参与标题行高度：
/// 有清除入口的分区与没有清除入口的分区标题行同高，标题到胶囊的视觉间距不会因此变大。
struct CapsuleSection<Content: View>: View {
    /// 分区标题。
    let title: String

    /// 清除按钮的无障碍文案；不传时按「清除 + 标题」生成。
    var clearAccessibilityLabel: String?

    /// 整段清除入口；为 `nil` 时不显示清除按钮。
    var onClear: (() -> Void)?

    @ContentBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(Color.textPrimary)

                Spacer(minLength: 8)
            }
            // 预留清除按钮的横向空间，长标题或大字号下不会伸到按钮下面；
            // 只占宽度、不占高度，标题行仍保持文字行高。
            .padding(.trailing, onClear == nil ? 0 : 44)
            .overlay(alignment: .trailing) {
                if let onClear {
                    Button(action: onClear) {
                        Image(systemName: "trash.fill")
                            .frame(width: 44, height: 44, alignment: .trailing)
                            .contentShape(Rectangle())
                    }
                    .font(.subheadline)
                    .foregroundStyle(Color.textSecondary)
                    .accessibilityLabel(clearAccessibilityLabel ?? "清除\(title)")
                }
            }

            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

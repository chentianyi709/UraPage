import SwiftUI
import UIKit

/// 以胶囊样式展示一组可点击的短文本：详情页的分类／标签、搜索页的热门搜索词与历史词共用。
///
/// 统一胶囊外观（`.caption` 中等字重、圆角、流式换行排布），配色由 `Style` 区分：
/// 分类／标签与热门搜索用品牌色，搜索历史用中性灰白底，避免历史词与热门词抢同一个视觉重点。
/// 传入 `onRemove` 时长按胶囊弹出系统菜单：复制文本、删除该条；常驻的删除按钮会被误触，所以放在长按里。
struct ComicCapsuleList: View {
    /// 胶囊配色。
    enum Style {
        /// 品牌色文字 + 品牌色 10% 底（分类、标签、热门搜索）。
        case brand

        /// 主文本 + 灰白底（搜索历史）。
        case neutral
    }

    /// 按展示顺序给出的原始值；重复值只保留首次出现。
    let values: [String]

    /// 胶囊配色，默认品牌色。
    var style: Style = .brand

    /// 长按删除某一条目的入口；`nil` 时长按不弹菜单。
    var onRemove: ((String) -> Void)?

    /// 点击某个胶囊。
    let onSelect: (String) -> Void

    var body: some View {
        WrappingFlowLayout(
            horizontalSpacing: 8,
            verticalSpacing: 8,
        ) {
            ForEach(uniqueValues, id: \.self) { value in
                chip(value)
                    // 删除只保留位置动画，被删的胶囊立刻离场：
                    // 默认的淡出过渡会在原地停留到动画结束，与补位过来的下一个胶囊重叠，
                    // 看起来就像「新位置的胶囊短暂显示了被删掉的那个名字」。
                    .transition(.asymmetric(insertion: .opacity, removal: .identity))
            }
        }
    }

    /// 单个胶囊；有删除入口时挂系统长按菜单。
    @ContentBuilder
    private func chip(_ value: String) -> some View {
        let capsule = Button {
            onSelect(value)
        } label: {
            Text(value)
                .font(.caption.weight(.medium))
                .foregroundStyle(textColor)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(backgroundColor, in: Capsule())
        }
        .buttonStyle(.plain)

        if let onRemove {
            capsule.contextMenu {
                Button("复制", systemImage: "doc.on.doc") {
                    // 直接写系统剪贴板；成功由 Toast 回执（系统本身不给反馈）。
                    UIPasteboard.general.string = value
                    ToastCenter.shared.show("已复制", type: .success)
                }
                // 菜单项默认跟随全局 tint（品牌红）；复制是中性的查看动作，用主文本色。
                .tint(Color.textPrimary)

                Button("删除", systemImage: "trash", role: .destructive) {
                    onRemove(value)
                }
            }
        } else {
            capsule
        }
    }

    /// 胶囊文字色。
    private var textColor: Color {
        switch style {
        case .brand: .brandPrimary
        case .neutral: .textPrimary
        }
    }

    /// 胶囊底色。
    private var backgroundColor: Color {
        switch style {
        case .brand: .brandPrimary.opacity(0.1)
        case .neutral: .fillNeutral
        }
    }

    /// 按原始顺序去重，避免重复胶囊使用相同 identity。
    private var uniqueValues: [String] {
        var seenValues: Set<String> = []
        return values.filter { seenValues.insert($0).inserted }
    }
}

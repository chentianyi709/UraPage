import SwiftUI

/// 以胶囊样式展示一组可点击的短文本：详情页的标签组（分类、标签、角色……）、搜索页的热门搜索词、历史词与收藏词共用。
///
/// 统一胶囊外观（`.caption` 中等字重、圆角、流式换行排布），配色由 `Style` 区分：
/// 标签组、热门搜索与收藏用品牌色，搜索历史用中性灰白底，避免历史词与热门词抢同一个视觉重点。
/// 长按菜单由调用方用 `@ContentBuilder` 逐条书写（与 `.contextMenu` 一致），组件不预设任何菜单项；
/// 不传菜单时胶囊保持普通按钮语义。
struct ComicCapsuleList<MenuContent: View>: View {
    /// 胶囊配色。
    enum Style {
        /// 品牌色文字 + 品牌色 10% 底（分类、标签、热门搜索、收藏）。
        case brand

        /// 主文本 + 灰白底（搜索历史）。
        case neutral
    }

    /// 按展示顺序给出的原始值；重复值只保留首次出现。
    let values: [String]

    /// 胶囊配色，默认品牌色。
    var style: Style = .brand

    /// 点击某个胶囊。
    let onSelect: (String) -> Void

    /// 某个胶囊的长按菜单内容；按词条生成，可含 `Button` 的分隔与 `role`。
    @ContentBuilder let menu: (String) -> MenuContent

    init(
        values: [String],
        style: Style = .brand,
        onSelect: @escaping (String) -> Void,
        @ContentBuilder menu: @escaping (String) -> MenuContent,
    ) {
        self.values = values
        self.style = style
        self.onSelect = onSelect
        self.menu = menu
    }

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

    /// 单个胶囊；调用方给了菜单时挂系统长按菜单。
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
        .accessibilityLabel(value)

        if MenuContent.self == EmptyView.self {
            capsule
        } else {
            capsule.contextMenu { menu(value) }
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

extension ComicCapsuleList where MenuContent == EmptyView {
    /// 没有长按菜单的胶囊列表（详情标签组、热门搜索）。
    init(values: [String], style: Style = .brand, onSelect: @escaping (String) -> Void) {
        self.init(values: values, style: style, onSelect: onSelect) { _ in EmptyView() }
    }
}

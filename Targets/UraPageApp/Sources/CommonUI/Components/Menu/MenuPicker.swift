import SwiftUI
import UIKit

/// 系统菜单样式的选择控件：点击弹出 `UIMenu`，每项「标题 + 副标题 + 勾选」。
///
/// 为什么不用 SwiftUI 的 `Menu` / `Picker(.menu)`：两者的选项只接受 `Text`，菜单项没有副标题槽位——
/// 选项里的 `VStack` 第二行会被整体丢弃，`AttributedString` 的字号与颜色也会被抹平（均已在模拟器实测）。
/// UIKit 的 `UIAction(title:subtitle:state:)` 在下拉菜单里能正常渲染副标题，外观、动画、勾选、
/// 点外关闭、键盘与辅助功能都由系统提供，因此这里用 `UIButton` + `UIMenu` 桥接一层。
///
/// 使用方只提供「菜单内容 + 当前选中 + 回调」；控件文字取选中项的标题，没有选中项时用 `placeholder`。
/// 配置变化只重建菜单，不重建按钮，避免菜单展开期间被替换。
struct MenuPicker<ID: Hashable>: UIViewRepresentable {
    /// 菜单内容（顺序即展示顺序）。
    let elements: [MenuPickerElement<ID>]

    /// 当前选中项；`nil` 时菜单项不显示勾选。
    let selection: ID?

    /// 是否可用；不可用时菜单不会弹出。
    var isEnabled = true

    /// 没有选中项（或选中项已不在菜单中）时控件显示的文字。
    var placeholder = ""

    /// 控件文字与箭头的颜色。
    var tint: Color = .brandPrimary

    /// 选中回调：点击任意一项都会回调，重复点击当前项是否忽略由调用方决定。
    let onSelect: @MainActor (ID) -> Void

    func makeUIView(context: Context) -> UIButton {
        let button = UIButton(configuration: Self.makeConfiguration(tint: tint))
        button.showsMenuAsPrimaryAction = true
        // 不参与 HStack 的等分布局：菜单控件按内容宽度占位。
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        return button
    }

    func updateUIView(_ button: UIButton, context: Context) {
        context.coordinator.onSelect = onSelect

        // 禁用态必须显式换色：classic/config 按钮在 iOS 26 都不会自动变灰。
        let foreground = isEnabled ? tint : Color.textTertiary
        var configuration = button.configuration ?? Self.makeConfiguration(tint: foreground)
        configuration.title = selectedTitle ?? placeholder
        configuration.image = Self.chevronImage(tint: foreground)
        // `UIButton.Configuration` 不吃按钮的 tintColor，标题与箭头颜色必须写在配置里。
        configuration.baseForegroundColor = UIColor(foreground)
        button.configuration = configuration

        button.tintColor = UIColor(foreground)
        button.isEnabled = isEnabled

        // 菜单内容没变就不重建 `UIMenu`，避免无关状态刷新替换正在展开的菜单。
        guard context.coordinator.shouldRebuildMenu(
            elements: elements,
            selection: selection,
        ) else { return }

        button.menu = SystemMenuBuilder.makeMenu(
            elements,
            selection: selection,
            onSelect: { context.coordinator.onSelect($0) },
        )
    }

    /// 有空间时用固有宽度，避免在 HStack 里被拉满而把文字和箭头拉开；
    /// 空间不足时允许压缩，避免长标题或大字号把整行撑出可用宽度。
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UIButton, context: Context) -> CGSize? {
        let intrinsic = uiView.intrinsicContentSize
        guard intrinsic.width > 0, let proposedWidth = proposal.width, proposedWidth.isFinite else {
            return intrinsic
        }

        return CGSize(width: min(intrinsic.width, proposedWidth), height: intrinsic.height)
    }

    func makeCoordinator() -> MenuHostCoordinator<ID> {
        MenuHostCoordinator(onSelect: onSelect)
    }

    /// 当前选中项的标题；菜单里没有该项时退回 `placeholder`。
    private var selectedTitle: String? {
        guard let selection else {
            return nil
        }

        return MenuPickerElement<ID>.title(matching: selection, in: elements)
    }

    /// 箭头按 tint 直接上色：`UIButton.Configuration` 的 `baseForegroundColor` 不一定作用于图标。
    private static func chevronImage(tint: Color) -> UIImage? {
        UIImage(
            systemName: "chevron.up.chevron.down",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 11, weight: .semibold),
        )?
            .withTintColor(UIColor(tint), renderingMode: .alwaysOriginal)
    }

    private static func makeConfiguration(tint: Color) -> UIButton.Configuration {
        var configuration = UIButton.Configuration.plain()
        configuration.image = chevronImage(tint: tint)
        configuration.imagePlacement = .trailing
        configuration.imagePadding = 5
        configuration.titleLineBreakMode = .byTruncatingTail
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0)
        // 跟随动态字号：UIKit 按钮不会自动用 preferred font。
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = UIFont.preferredFont(forTextStyle: .body)
            return outgoing
        }
        return configuration
    }
}

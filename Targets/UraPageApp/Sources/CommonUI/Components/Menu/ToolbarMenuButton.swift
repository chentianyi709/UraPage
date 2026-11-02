import SwiftUI
import UIKit

/// 工具栏里的图标菜单：点击弹出 `UIMenu`，内容与 `MenuPicker` 共用 `MenuPickerElement`
/// （支持副标题、分割线与二级菜单）。
///
/// 与 `MenuPicker` 的区别只在触发件：这里没有文字和箭头，只有一个 SF Symbol；
/// 图标颜色由调用方给出（例如「当前筛选偏离默认值」时用品牌色）。
struct ToolbarMenuButton<ID: Hashable>: UIViewRepresentable {
    /// 菜单内容（顺序即展示顺序）。
    let elements: [MenuPickerElement<ID>]

    /// 当前选中项；`nil` 时菜单项不显示勾选。
    let selection: ID?

    /// 触发件使用的 SF Symbol。
    let systemImage: String

    /// 图标颜色。
    var tint: Color = .textPrimary

    /// 无障碍标签与值（图标没有文字，必须显式给出，否则读屏只剩「按钮」）。
    var accessibilityLabel: String?
    var accessibilityValue: String?

    /// 选中回调。
    let onSelect: @MainActor (ID) -> Void

    func makeUIView(context: Context) -> UIButton {
        // 用 classic 按钮而不是 `UIButton.Configuration`：配置式按钮在 iOS 26 的工具栏里会被套上玻璃胶囊底。
        let button = UIButton(type: .system)
        button.setImage(Self.image(named: systemImage, tint: tint), for: .normal)
        button.showsMenuAsPrimaryAction = true
        return button
    }

    func updateUIView(_ button: UIButton, context: Context) {
        context.coordinator.onSelect = onSelect

        button.setImage(Self.image(named: systemImage, tint: tint), for: .normal)
        button.tintColor = UIColor(tint)
        button.accessibilityLabel = accessibilityLabel
        button.accessibilityValue = accessibilityValue

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

    /// 固定方形尺寸（图标 17pt 居中）：既不会被工具栏撑成一条，也不依赖配置式的胶囊底。
    ///
    /// 边长必须小于导航栏玻璃底的高度上限，否则系统会把底压成横向椭圆（见 `ToolbarControlMetrics`）。
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UIButton, context: Context) -> CGSize? {
        CGSize(width: ToolbarControlMetrics.side, height: ToolbarControlMetrics.side)
    }

    func makeCoordinator() -> MenuHostCoordinator<ID> {
        MenuHostCoordinator(onSelect: onSelect)
    }

    /// 图标按 tint 直接上色：`UIButton.Configuration` 的 `baseForegroundColor` 在工具栏里会被系统覆盖。
    private static func image(named systemImage: String, tint: Color) -> UIImage? {
        UIImage(
            systemName: systemImage,
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .regular),
        )?
            .withTintColor(UIColor(tint), renderingMode: .alwaysOriginal)
    }
}

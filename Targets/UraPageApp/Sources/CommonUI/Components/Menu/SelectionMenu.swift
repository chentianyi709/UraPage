import SwiftUI

/// 使用页面传入的数据、图标和文案渲染右上角筛选菜单。
///
/// 渲染交给公共 `ToolbarMenuButton`（UIKit 图标菜单）：菜单项支持任意层子菜单，
/// 外观、动画、勾选与点外关闭都是系统行为。
/// 传入 `defaultID` 时，若当前选择不是该默认项，图标用品牌色提示「当前有非默认筛选」，
/// 并给无障碍值「已启用筛选」；传入 `nil`（不需要提示的调用点）时行为与以前一致。
struct SelectionMenu: View {
    let items: [SelectionMenuItem]
    let selectedID: String?

    /// 该条件的默认选项 id；`nil` 表示不启用「非默认高亮」。
    var defaultID: String?

    let isLoading: Bool
    let systemImage: String
    let accessibilityLabel: String
    let loadingAccessibilityLabel: String
    let onSelect: @MainActor (String) -> Void

    /// 仅当提供了默认项且当前选择偏离它时，图标用品牌色（只变色，不改菜单内容）。
    private var isActive: Bool {
        guard let defaultID else {
            return false
        }

        return selectedID != defaultID
    }

    var body: some View {
        if isLoading {
            // 与菜单按钮同尺寸预留：加载完成时工具栏不左右跳。
            ProgressView()
                .controlSize(.small)
                .tint(Color.brandPrimary)
                .frame(width: ToolbarControlMetrics.side, height: ToolbarControlMetrics.side)
                .accessibilityLabel(loadingAccessibilityLabel)
        } else if !items.isEmpty {
            ToolbarMenuButton(
                elements: elements,
                selection: selectedID,
                systemImage: systemImage,
                tint: isActive ? Color.brandPrimary : Color.textPrimary,
                accessibilityLabel: accessibilityLabel,
                accessibilityValue: isActive ? "已启用筛选" : "默认",
                onSelect: onSelect,
            )
        }
    }

    /// 把 `SelectionMenuItem` 树转换成菜单内容树。
    private var elements: [MenuPickerElement<String>] {
        items.map(Self.element(for:))
    }

    private static func element(for item: SelectionMenuItem) -> MenuPickerElement<String> {
        guard !item.children.isEmpty else {
            return .item(id: item.id, title: item.title, subtitle: nil)
        }

        // 子菜单行没有独立的选中位：父项若可被选中，id 必须由某个子项承载（各来源用第一项「全部」表示）。
        return .submenu(title: item.title, children: item.children.map(element(for:)))
    }
}

/// 菜单选项：`id` 为稳定选择标识，`children` 非空时渲染为子菜单。
struct SelectionMenuItem: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let children: [SelectionMenuItem]

    init(id: String, title: String, children: [SelectionMenuItem] = []) {
        self.id = id
        self.title = title
        self.children = children
    }
}

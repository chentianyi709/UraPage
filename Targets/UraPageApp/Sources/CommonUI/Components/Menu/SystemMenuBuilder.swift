import UIKit

/// 把 `MenuPickerElement` 树构建成 `UIMenu`。
///
/// 由 `MenuPicker`（文字触发）与 `ToolbarMenuButton`（图标触发）共用，两处只有触发件外观不同，
/// 菜单内容、分割线与子菜单的表现完全一致。
@MainActor
enum SystemMenuBuilder {
    static func makeMenu<ID: Hashable>(
        _ elements: [MenuPickerElement<ID>],
        selection: ID?,
        onSelect: @escaping @MainActor (ID) -> Void,
    ) -> UIMenu {
        UIMenu(children: makeElements(elements, selection: selection, onSelect: onSelect))
    }

    /// 把一层内容按分割线切成若干组，再交给 `UIMenu` 渲染。
    ///
    /// 只有一组时直接平铺（没有多余的分隔）；多组时每组包成 `displayInline` 子菜单，
    /// `UIMenu` 会在相邻组之间渲染分割线。
    private static func makeElements<ID: Hashable>(
        _ elements: [MenuPickerElement<ID>],
        selection: ID?,
        onSelect: @escaping @MainActor (ID) -> Void,
    ) -> [UIMenuElement] {
        var sections: [[MenuPickerElement<ID>]] = [[]]
        for element in elements {
            if case .separator = element {
                if sections[sections.count - 1].isEmpty {
                    continue
                }

                sections.append([])
            } else {
                sections[sections.count - 1].append(element)
            }
        }

        let filledSections = sections.filter { !$0.isEmpty }
        guard filledSections.count > 1 else {
            return makeItems(filledSections.first ?? [], selection: selection, onSelect: onSelect)
        }

        return filledSections.map { section in
            UIMenu(
                title: "",
                options: .displayInline,
                children: makeItems(section, selection: selection, onSelect: onSelect),
            )
        }
    }

    /// 渲染一组内容为一维菜单元素；子菜单递归走 `children`，因此也支持分割线与更深层嵌套。
    private static func makeItems<ID: Hashable>(
        _ elements: [MenuPickerElement<ID>],
        selection: ID?,
        onSelect: @escaping @MainActor (ID) -> Void,
    ) -> [UIMenuElement] {
        elements.compactMap { element -> UIMenuElement? in
            switch element {
            case let .item(id, title, subtitle):
                UIAction(
                    title: title,
                    subtitle: subtitle,
                    state: id == selection ? .on : .off,
                ) { _ in
                    // UIKit 的菜单动作在主线程投递；主 actor 约束在这里统一承接，
                    // 调用方不必各自再包 `MainActor.assumeIsolated`。
                    MainActor.assumeIsolated {
                        onSelect(id)
                    }
                }

            case let .submenu(title, kids):
                // 子菜单行没有 `state`：选中项在子树里时在标题后标注，否则用户得逐层点开才知道当前值。
                // 不用 `UIMenu` 的 `image`，那会占用独立图标槽位、把该行标题右推。
                UIMenu(
                    title: submenuTitle(title, children: kids, selection: selection),
                    children: makeElements(
                        kids,
                        selection: selection,
                        onSelect: onSelect,
                    ),
                )

            case .separator:
                nil
            }
        }
    }

    /// 子菜单标题：选中项在子树里时追加「已选」。
    private static func submenuTitle<ID: Hashable>(
        _ title: String,
        children: [MenuPickerElement<ID>],
        selection: ID?,
    ) -> String {
        guard let selection, MenuPickerElement<ID>.contains(selection, in: children) else {
            return title
        }

        return "\(title) · 已选"
    }
}

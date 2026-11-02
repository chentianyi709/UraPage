/// 菜单内容：可选中项、分割线、二级菜单（可继续嵌套）。
///
/// 用树而不用扁平数组，是因为 `UIMenu` 本身就支持子菜单与分组；
/// 分割线在 `UIMenu` 里没有独立元素，由「组与组之间」隐式渲染，所以这里只标记分组边界。
///
/// - Note: `UIMenu` 的子菜单行没有独立的选中状态。若子菜单本身也可被选中，父项 id 必须由某个
///   子项承载（当前来源用第一项「全部」表示），`SystemMenuBuilder` 只能从子项判断父行的选中提示。
enum MenuPickerElement<ID: Hashable>: Equatable {
    /// 可选中项；`subtitle` 会渲染成标题下方的小号灰字。
    case item(id: ID, title: String, subtitle: String?)

    /// 与上一组之间的分割线；开头或连续多条会被忽略。
    case separator

    /// 二级菜单，内部同样支持分割线与更深层子菜单。
    case submenu(title: String, children: [MenuPickerElement<ID>])
}

extension MenuPickerElement {
    /// 无副标题的项。
    static func item(id: ID, title: String) -> Self {
        .item(id: id, title: title, subtitle: nil)
    }

    /// 在树里查找选中项的标题（选中项可能在任意一层子菜单）。
    static func title(matching selection: ID, in elements: [MenuPickerElement<ID>]) -> String? {
        for element in elements {
            switch element {
            case let .item(id, title, _):
                if id == selection {
                    return title
                }

            case let .submenu(_, children):
                if let title = title(matching: selection, in: children) {
                    return title
                }

            case .separator:
                continue
            }
        }

        return nil
    }

    /// 这棵树里是否包含指定项（用于子菜单标题的「已选」提示，选中项可能在任何一层）。
    static func contains(_ selection: ID, in elements: [MenuPickerElement<ID>]) -> Bool {
        for element in elements {
            switch element {
            case let .item(id, _, _):
                if id == selection {
                    return true
                }

            case let .submenu(_, children):
                if contains(selection, in: children) {
                    return true
                }

            case .separator:
                continue
            }
        }

        return false
    }
}

/// `MenuPicker` 与 `ToolbarMenuButton` 共用的菜单协调器。
///
/// 两个触发件只有外观不同，回调更新与「菜单输入未变化时不重建 `UIMenu`」的规则完全一致；
/// 规则放在一处，避免一份改了另一份漏掉。
@MainActor
final class MenuHostCoordinator<ID: Hashable> {
    var onSelect: @MainActor (ID) -> Void

    /// 上次构建菜单所用的输入；内容相同就不重建。
    private var menuElements: [MenuPickerElement<ID>]?
    private var menuSelection: ID?

    init(onSelect: @escaping @MainActor (ID) -> Void) {
        self.onSelect = onSelect
    }

    func shouldRebuildMenu(
        elements: [MenuPickerElement<ID>],
        selection: ID?,
    ) -> Bool {
        guard menuElements != elements || menuSelection != selection else {
            return false
        }

        menuElements = elements
        menuSelection = selection
        return true
    }
}

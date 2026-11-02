import SwiftUI

/// 在系统 Toolbar 的可用区域内居中显示 Reader 漫画标题，并在右侧显示阅读设置入口。
/// 两项均使用系统 Toolbar 默认玻璃，不在内容上重复添加玻璃材质。
struct ReaderChromeToolbar: ToolbarContent {
    let title: String
    let onOpenSettings: () -> Void

    var body: some ToolbarContent {
        // 标题填满系统分配的可用区域，使短标题也在该区域内居中显示。
        ToolbarItem {
            Text(title)
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
        }

        ToolbarSpacer(.fixed)

        ToolbarItem(placement: .topBarTrailing) {
            Button(action: onOpenSettings) {
                Image(systemName: "gearshape")
            }
            .tint(.primary)
            .accessibilityLabel("阅读设置")
        }
    }
}

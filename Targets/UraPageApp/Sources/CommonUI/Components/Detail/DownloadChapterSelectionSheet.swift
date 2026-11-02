import SwiftUI

/// 详情页「下载」按钮在多章节漫画时弹出的选章弹窗。
///
/// 复用公共 `ChapterGridSheet` 的网格与列数/正反序外壳；本视图只负责多选与状态展示，
/// 确认时回传所选章节身份，由 `.comicDetailDownload` 接线的控制器入队，自身不发起下载。
struct DownloadChapterSelectionSheet: View {
    @Environment(\.dismiss) private var dismiss

    let items: [DownloadChapterSelectionItem]

    /// 用户确认的章节身份集合（“开始下载”的时机交给调用方）。
    let onConfirm: (Set<ChapterIdentity>) -> Void

    @State private var selected: Set<ChapterIdentity> = []

    init(
        items: [DownloadChapterSelectionItem],
        onConfirm: @escaping (Set<ChapterIdentity>) -> Void,
    ) {
        self.items = items
        self.onConfirm = onConfirm
    }

    var body: some View {
        ChapterGridSheet(
            title: "选择下载章节（\(items.count)）",
            items: items,
        ) { item in
            chapterCell(item)
        } bottomBar: {
            ToolbarItem(placement: .bottomBar) {
                selectAllButton
            }

            ToolbarSpacer(.flexible, placement: .bottomBar)

            ToolbarItem(placement: .bottomBar) {
                confirmButton
            }

            ToolbarSpacer(.flexible, placement: .bottomBar)
        }
    }

    /// 单个章节：仅展示章节标题；可选项点击切换勾选，其它状态通过按钮禁用表达。
    private func chapterCell(_ item: DownloadChapterSelectionItem) -> some View {
        Button {
            toggleSelection(item)
        } label: {
            Text(item.title)
                .font(.footnote.weight(.semibold))
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(background(for: item))
                }
        }
        .buttonStyle(.plain)
        .foregroundStyle(foreground(for: item))
        .disabled(!item.isSelectable)
        .accessibilityValue(accessibilityValue(for: item))
    }

    /// 底部左侧「全选/取消全选」图标按钮。
    private var selectAllButton: some View {
        Button {
            toggleSelectAll()
        } label: {
            Image(systemName: "checkmark")
        }
        .disabled(selectableItems.isEmpty)
        .tint(allSelectableSelected ? Color.brandPrimary : Color.textPrimary)
        .accessibilityLabel(allSelectableSelected ? "取消全选" : "全选")
    }

    /// 底部中间的「下载所选」文字按钮：不用背景色，改用文字颜色表示可下载（品牌色）。
    private var confirmButton: some View {
        Button {
            onConfirm(selected)
            dismiss()
        } label: {
            Text(confirmTitle)
                .font(.body.weight(.semibold))
                .foregroundStyle(selected.isEmpty ? Color.textSecondary : Color.brandPrimary)
        }
        .disabled(selected.isEmpty)
        .accessibilityLabel("下载所选")
    }

    private var confirmTitle: String {
        selected.isEmpty ? "下载所选" : "下载所选（\(selected.count)）"
    }

    private var allSelectableSelected: Bool {
        !selectableItems.isEmpty && selectableItems.allSatisfy(isSelected)
    }

    // MARK: - 选择

    private func toggleSelection(_ item: DownloadChapterSelectionItem) {
        guard item.isSelectable else {
            return
        }

        if selected.contains(item.identity) {
            selected.remove(item.identity)
        } else {
            selected.insert(item.identity)
        }
    }

    private func toggleSelectAll() {
        if selectableItems.allSatisfy(isSelected) {
            selected.subtract(selectableItems.map(\.identity))
        } else {
            selected.formUnion(selectableItems.map(\.identity))
        }
    }

    private func isSelected(_ item: DownloadChapterSelectionItem) -> Bool {
        selected.contains(item.identity)
    }

    // MARK: - 展示

    private var selectableItems: [DownloadChapterSelectionItem] {
        items.filter(\.isSelectable)
    }

    private func background(for item: DownloadChapterSelectionItem) -> Color {
        if isSelected(item) {
            Color.brandPrimary
        } else if item.isSelectable {
            Color.surface
        } else {
            Color.surfaceElevated
        }
    }

    private func foreground(for item: DownloadChapterSelectionItem) -> Color {
        if isSelected(item) {
            Color.textOnPrimary
        } else if item.isSelectable {
            Color.textPrimary
        } else {
            Color.textTertiary
        }
    }

    private func accessibilityValue(for item: DownloadChapterSelectionItem) -> String {
        if let accessibilityStatus = item.accessibilityStatus {
            return accessibilityStatus
        }

        return isSelected(item) ? "已选择" : "未选择"
    }
}

extension View {
    /// 安装下载选章弹窗（多章节漫画）；呈现样式与章节弹窗一致。
    func downloadChapterSelectionSheet(
        isPresented: Binding<Bool>,
        items: [DownloadChapterSelectionItem],
        onConfirm: @escaping (Set<ChapterIdentity>) -> Void,
    ) -> some View {
        sheet(isPresented: isPresented) {
            DownloadChapterSelectionSheet(
                items: items,
                onConfirm: onConfirm,
            )
            .presentationDetents([.fraction(2.0 / 3.0), .large])
            .presentationBackground(Color.pageBackground)
            .presentationDragIndicator(.visible)
        }
    }
}

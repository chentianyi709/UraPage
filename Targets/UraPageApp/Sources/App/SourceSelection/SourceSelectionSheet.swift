import Foundation
import SwiftUI

/// 在紧凑的底部 Sheet 中展示全部来源，支持切换与系统拖动排序。
///
/// 只负责展示与回调：切换由 App Shell 执行（释放旧体验、关闭图片工作域、恢复轻量导航）。
/// 弹窗外观（高度、背景、拖拽指示）由本视图自己声明：所有 App 级弹窗同一规则，
/// `AppShellView` 的 `sheetContent` 只负责构造内容。
struct SourceSelectionSheet: View {
    @Environment(\.dismiss) private var dismiss

    /// 按用户排序展示的来源清单。
    let sources: [SourceDescriptor]

    /// 当前激活来源；切换过程中仍显示原选择。
    let currentSourceID: ComicSourceID?

    /// 正在切换来源：期间禁用全部行，避免重复提交。
    let isSwitching: Bool

    let onSelect: (ComicSourceID) -> Void
    let onMove: (IndexSet, Int) -> Void

    /// 分割线起点相对行内容左缘的偏移：与来源名文字左缘对齐。
    /// `nonisolated` 供 `alignmentGuide` 的 `@Sendable` 闭包读取。
    private nonisolated static let rowSeparatorTextLeading: CGFloat = 40

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(sources, id: \.sourceID) { source in
                        sourceButton(source)
                            .moveDisabled(isSwitching)
                            // 固定分割线起点对齐文字：SwiftUI 自动计算的 leading inset
                            // 在 onMove 重排后不会对每个 cell 重新套用，导致长短不一。
                            .alignmentGuide(.listRowSeparatorLeading) { _ in
                                Self.rowSeparatorTextLeading
                            }
                    }
                    .onMove(perform: onMove)
                }
            }
            .listStyle(.insetGrouped)
            .environment(\.editMode, .constant(.active))
            .contentMargins(.top, 8, for: .scrollContent)
            .scrollDisabled(true)
            .navigationTitle("选择漫画源")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: dismiss.callAsFunction) {
                        Image(systemName: "xmark")
                            .foregroundStyle(Color.textPrimary)
                    }
                    .tint(Color.textPrimary)
                    .accessibilityLabel("关闭")
                }
            }
        }
        .appNavigationBarScrollEdgeEffect()
        .presentationDetents([.height(320)])
        .presentationBackground(Color.pageBackground)
        .presentationDragIndicator(.hidden)
    }

    /// 展示一个来源，并用系统勾选图标标记当前选择。
    private func sourceButton(_ source: SourceDescriptor) -> some View {
        let isSelected = source.sourceID == currentSourceID

        return Button {
            onSelect(source.sourceID)
        } label: {
            HStack(spacing: 12) {
                SourceLogoView(source.logo, size: 28)

                Text(source.displayName)

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.brandPrimary)
                        .accessibilityHidden(true)
                }
            }
            .frame(minHeight: 44)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(isSwitching)
        .accessibilityValue(Text(isSelected ? "当前选择" : ""))
    }
}

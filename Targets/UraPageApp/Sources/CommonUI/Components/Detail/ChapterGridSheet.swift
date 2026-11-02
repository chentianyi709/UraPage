import SwiftUI

/// 章节网格弹窗的公共外壳：网格布局 + 列数/正反序/关闭工具栏，内容与底部工具栏为槽位。
///
/// 「章节列表」弹窗（单选取章）与「下载选章」弹窗（多选）共用；本视图不持有选择状态，
/// 只负责网格布局、列数与正反序（跨来源共享 `AppearanceSettingsStore`）。
struct ChapterGridSheet<Item: Identifiable, Cell: View, BottomBar: ToolbarContent>: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appearanceSettings) private var appearanceSettings

    let title: String
    let items: [Item]

    @ContentBuilder let cell: (Item) -> Cell

    /// 底部工具栏槽位；无底部内容时传一个空 `ToolbarItemGroup`。
    @ContentBuilder let bottomBar: () -> BottomBar

    @State private var isReversed = false

    init(
        title: String,
        items: [Item],
        @ContentBuilder cell: @escaping (Item) -> Cell,
        @ContentBuilder bottomBar: @escaping () -> BottomBar,
    ) {
        self.title = title
        self.items = items
        self.cell = cell
        self.bottomBar = bottomBar
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(displayedItems) { item in
                        cell(item)
                    }
                }
                .padding(16)
            }
            .scrollBounceBehavior(.basedOnSize)
            .background(Color.pageBackground)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarLeading) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            appearanceSettings.selectChapterSheetColumnCount(nextColumnCount)
                        }
                    } label: {
                        Image(systemName: layoutSystemImage)
                    }
                    .accessibilityLabel("切换为\(nextColumnCount)列布局")
                    .tint(.primary)

                    Button {
                        isReversed.toggle()
                    } label: {
                        Image(systemName: "arrow.up")
                            .rotationEffect(.degrees(isReversed ? 180 : 0))
                            .animation(.easeInOut(duration: 0.2), value: isReversed)
                    }
                    .accessibilityLabel(isReversed ? "切换为正序" : "切换为倒序")
                    .tint(.primary)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("关闭")
                    .tint(.primary)
                }

                bottomBar()
            }
        }
        .appNavigationBarScrollEdgeEffect()
    }

    private var columns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(), spacing: 10),
            count: appearanceSettings.chapterSheetColumnCount,
        )
    }

    private var displayedItems: [Item] {
        isReversed ? Array(items.reversed()) : items
    }

    private var nextColumnCount: Int {
        appearanceSettings.chapterSheetColumnCount == 1 ? 3 : appearanceSettings.chapterSheetColumnCount - 1
    }

    private var layoutSystemImage: String {
        switch appearanceSettings.chapterSheetColumnCount {
        case 3: "square.grid.3x3"
        case 2: "square.grid.2x2"
        default: "rectangle.grid.1x2"
        }
    }
}

import SwiftUI

/// 搜索页引导区的「最近搜索」：标题 + 整段清除入口 + 关键词胶囊（`ComicCapsuleList` 的中性配色）。
///
/// 单条操作走长按胶囊弹出的菜单（复制文本／删除）——胶囊常驻删除按钮容易被误触，
/// 收起后点词只会执行搜索；标题右侧的实心垃圾桶清整段。两者都不做二次确认：历史由搜索行为重新生成，
/// 单条也没有可恢复的内容。版式走公共 `CapsuleSection`，与书签页、热门搜索共用标题与间距。
/// 只负责排版；引导区只有搜索历史的来源用 `SearchHistorySection` 套滚动容器，
/// 还需要组合热门搜索等其它引导内容的页面自行放进外层容器。
struct SearchHistoryView: View {
    let queries: [String]
    let onSelect: (String) -> Void
    let onRemove: (String) -> Void
    let onClear: () -> Void

    @State private var showsClearConfirmation = false

    var body: some View {
        CapsuleSection(
            title: "最近搜索",
            clearAccessibilityLabel: "清除搜索历史",
            onClear: { showsClearConfirmation = true },
        ) {
            ComicCapsuleList(
                values: queries,
                style: .neutral,
                onRemove: onRemove,
                onSelect: onSelect,
            )
        }
        .alert("清除搜索历史？", isPresented: $showsClearConfirmation) {
            Button("取消", role: .cancel) {}
            Button("清除", role: .destructive) {
                onClear()
            }
        } message: {
            Text("将清除本来源的全部搜索历史。")
        }
    }
}

/// 搜索页引导区的历史区外壳：滚动容器、内边距与隐藏指示器。
///
/// 用于引导区只有搜索历史的来源（绅士）；禁漫与哔咔的引导区还包含热门搜索，
/// 继续自行组合 `SearchHistoryView`，避免把两种版式混进同一个组件。
struct SearchHistorySection: View {
    let queries: [String]
    let onSelect: (String) -> Void
    let onRemove: (String) -> Void
    let onClear: () -> Void

    var body: some View {
        ScrollView {
            SearchHistoryView(
                queries: queries,
                onSelect: onSelect,
                onRemove: onRemove,
                onClear: onClear,
            )
            .padding(16)
        }
        .scrollIndicators(.hidden)
    }
}

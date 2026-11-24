import SwiftUI

/// 搜索页引导区的「最近搜索」：标题 + 整段清除入口 + 关键词胶囊（`ComicCapsuleList` 的中性配色）。
///
/// 列表里只有未收藏的词——收藏后即刻从这段移出，取消收藏按最近一次搜索时间回来（见 `SearchHistoryViewModel`）。
/// 单条操作走长按胶囊弹出的菜单（收藏、复制文本、删除该条）——胶囊常驻按钮容易被误触，
/// 收起后点词只会执行搜索；标题右侧的实心垃圾桶清整段，收藏的搜索词不受影响。
/// 版式走公共 `CapsuleSection`，与书签页、热门搜索共用标题与间距。
/// 只负责「最近搜索」这一段；与收藏区的组合见 `SearchHistorySection`。
struct SearchHistoryView: View {
    let history: SearchHistoryViewModel
    let onSelect: (String) -> Void

    @State private var showsClearConfirmation = false

    var body: some View {
        CapsuleSection(
            title: "最近搜索",
            clearAccessibilityLabel: "清除搜索历史",
            onClear: { showsClearConfirmation = true },
        ) {
            ComicCapsuleList(
                values: history.queries,
                style: .neutral,
                onSelect: onSelect,
            ) { query in
                Button("收藏", systemImage: "star") {
                    Task { await history.favorite(query) }
                }
                .tint(Color.textPrimary)

                Button("复制", systemImage: "doc.on.doc") {
                    UIPasteboard.general.string = query
                    ToastCenter.shared.show("已复制", type: .success)
                }
                .tint(Color.textPrimary)

                Button("删除", systemImage: "trash", role: .destructive) {
                    Task { await history.remove(query) }
                }
            }
        }
        .alert(isPresented: $showsClearConfirmation) {
            Alert(
                title: Text("清除搜索历史？"),
                message: Text("将清除本来源的最近搜索，收藏的搜索词会保留。"),
                primaryButton: .destructive(Text("清除")) {
                    Task { await history.clear() }
                },
                secondaryButton: .cancel(Text("取消")),
            )
        }
    }
}

/// 搜索页引导区的历史区组合：收藏区在上、最近搜索在下。
///
/// 两个分区读同一份历史数据（收藏与否由 `favoritedAt` 决定），同一条词只会出现在其中一处。
/// 三个来源共用这一份组合；需要滚动容器的页面自行在外面套 `ScrollView`。
struct SearchHistorySection: View {
    let history: SearchHistoryViewModel
    let onSelect: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            if !history.favorites.isEmpty {
                FavoriteSearchView(history: history, onSelect: onSelect)
            }

            if !history.queries.isEmpty {
                SearchHistoryView(history: history, onSelect: onSelect)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

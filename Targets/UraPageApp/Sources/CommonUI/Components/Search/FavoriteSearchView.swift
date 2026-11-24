import SwiftUI

/// 搜索页引导区的「收藏的搜索词」：标题 + 品牌色胶囊（与热门搜索同款），排在「最近搜索」之上。
///
/// 单条操作走长按菜单（取消收藏／复制）；点击与历史词一致，填入并立即搜索。
/// 标题右侧的垃圾桶整段删除收藏——这些词不会回到「最近搜索」。
/// 收藏不参与历史裁剪，也不随「清除搜索历史」消失。
struct FavoriteSearchView: View {
    let history: SearchHistoryViewModel
    let onSelect: (String) -> Void

    @State private var showsClearConfirmation = false

    var body: some View {
        CapsuleSection(
            title: "收藏的搜索词",
            clearAccessibilityLabel: "删除收藏的搜索词",
            onClear: { showsClearConfirmation = true },
        ) {
            ComicCapsuleList(
                values: history.favorites,
                style: .brand,
                onSelect: onSelect,
            ) { query in
                Button("取消收藏", systemImage: "star.slash") {
                    Task { await history.unfavorite(query) }
                }
                .tint(Color.textPrimary)

                Button("复制", systemImage: "doc.on.doc") {
                    UIPasteboard.general.string = query
                    ToastCenter.shared.show("已复制", type: .success)
                }
                .tint(Color.textPrimary)
            }
        }
        .alert("删除收藏的搜索词？", isPresented: $showsClearConfirmation) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) {
                Task { await history.clearFavorites() }
            }
        } message: {
            Text("将永久删除这些收藏的搜索词，不会回到「最近搜索」。")
        }
    }
}

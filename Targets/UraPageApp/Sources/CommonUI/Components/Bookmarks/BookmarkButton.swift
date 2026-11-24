import SwiftUI

/// 分类／标签列表页右上角的收藏按钮：读取当前收藏态并就地切换。
///
/// 收藏态与写入都走 `BookmarkStore`（书签库）；作者页用 `FollowingButton`，两者不共用存储。
struct BookmarkButton: View {
    @Environment(\.bookmarkStore) private var store

    /// 来源的书签维度目录：按钮只借它把维度标识翻译成展示名称。
    @Environment(\.sourceDescriptor) private var descriptor

    /// 当前页面代表的那一条书签。
    let bookmark: Bookmark

    var body: some View {
        MarkButton(
            identity: "\(bookmark.sourceID.rawValue)|\(bookmark.kindID)|\(bookmark.displayName)",
            labels: MarkButton.Labels(
                subject: "\(kindTitle)：\(bookmark.displayName)",
                onTitle: "收藏",
                offTitle: "取消收藏",
                failureMessage: { target in
                    target ? "收藏失败，请稍后重试" : "取消收藏失败，请稍后重试"
                },
                logCategory: "Bookmarks",
            ),
            read: {
                try await store.isFavorite(bookmark)
            },
            write: { target in
                if target {
                    try await store.save(bookmark)
                } else {
                    try await store.remove(bookmark)
                }
            },
        )
    }

    /// 维度名称：来源目录里有就用目录的，没有（来源已移除该维度）就退回标识本身。
    private var kindTitle: String {
        descriptor.tagKind(id: bookmark.kindID)?.title ?? ComicTagKind.unknown(bookmark.kindID).title
    }
}

extension EnvironmentValues {
    /// 书签收藏进程级入口存储槽；写入用 `\.bookmarkStoreStorage`。
    @Entry var bookmarkStoreStorage: BookmarkStore?

    /// 读取入口：由 App 入口安装，未安装即暴露装配错误。
    var bookmarkStore: BookmarkStore {
        guard let bookmarkStoreStorage else {
            preconditionFailure("bookmarkStore 未由 App 入口安装")
        }

        return bookmarkStoreStorage
    }
}

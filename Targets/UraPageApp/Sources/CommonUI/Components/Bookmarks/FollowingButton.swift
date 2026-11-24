import SwiftUI

/// 作者列表页右上角的关注按钮：读取当前关注态并就地切换。
///
/// 关注态与写入都走 `FollowingStore`（关注库）；分类／标签页用 `BookmarkButton`，两者不共用存储。
struct FollowingButton: View {
    @Environment(\.followingStore) private var store

    /// 当前页面代表的那位作者。
    let following: Following

    var body: some View {
        MarkButton(
            identity: "\(following.sourceID.rawValue)|\(following.name)",
            labels: MarkButton.Labels(
                subject: "作者：\(following.name)",
                onTitle: "关注",
                offTitle: "删除",
                failureMessage: { target in
                    target ? "关注失败，请稍后重试" : "删除失败，请稍后重试"
                },
                logCategory: "Followings",
            ),
            read: {
                try await store.contains(following)
            },
            write: { target in
                if target {
                    try await store.save(following)
                } else {
                    try await store.remove(following)
                }
            },
        )
    }
}

extension EnvironmentValues {
    /// 关注作者进程级入口存储槽；写入用 `\.followingStoreStorage`。
    @Entry var followingStoreStorage: FollowingStore?

    /// 读取入口：由 App 入口安装，未安装即暴露装配错误。
    var followingStore: FollowingStore {
        guard let followingStoreStorage else {
            preconditionFailure("followingStore 未由 App 入口安装")
        }

        return followingStoreStorage
    }
}

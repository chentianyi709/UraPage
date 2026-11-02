import SwiftUI

/// 标签／作者／分类列表页右上角的收藏按钮：读取当前收藏态并就地切换。
///
/// 收藏态由书签 store 异步读取；点击直接切换并落盘，失败回滚并提示，
/// 与搜索历史的乐观更新规则一致。按钮不固定 44×44 命中区：导航栏内容高度不足 44，
/// 固定方框会被压成椭圆底；交给系统按图标包一圈玻璃，和返回按钮一样是正的圆。
struct BookmarkButton: View {
    @Environment(\.bookmarkStore) private var store

    /// 当前页面代表的那一条书签。
    let bookmark: Bookmark

    @State private var isFavorite: Bool?

    /// 触觉反馈计数：只在用户点击时自增，读取收藏态不会触发。
    @State private var feedbackCount = 0

    var body: some View {
        Button {
            toggle()
        } label: {
            Image(systemName: isFavorite == true ? "heart.fill" : "heart")
                .foregroundStyle(isFavorite == true ? Color.brandPrimary : Color.textPrimary)
        }
        .accessibilityLabel(
            "\(isFavorite == true ? "取消收藏" : "收藏")，\(bookmark.kind.title)：\(bookmark.displayName)",
        )
        .accessibilityAddTraits(isFavorite == true ? .isSelected : [])
        .sensoryFeedback(.impact(weight: .light), trigger: feedbackCount)
        .disabled(isFavorite == nil)
        .task(id: bookmark.identityKey) {
            // 同一页面切换书签时先回到未知态，避免旧收藏态短暂套到新条目上。
            isFavorite = nil

            do {
                let saved = try await store.isFavorite(bookmark)
                guard !Task.isCancelled else { return }

                isFavorite = saved
            } catch {
                guard !Task.isCancelled else { return }

                AppLogger.warning(
                    "书签收藏读取失败，source=\(bookmark.sourceID.rawValue) kind=\(bookmark.kind.rawValue) "
                        + "errorType=\(type(of: error))",
                    category: "Bookmarks",
                )
                isFavorite = false
            }
        }
    }

    /// 点击即切换本地展示并落盘；失败回滚。
    ///
    /// 收藏态只在这里读取一次（`.task`），点击不再二次查询 store：
    /// 未读完前按钮禁用，读完后「看到什么就切换成相反」，不会出现点了取消却又收藏。
    private func toggle() {
        guard let current = isFavorite else { return }

        // 点击即给触觉反馈，不等落盘；读取收藏态的那点延迟不该让手感变钝。
        feedbackCount &+= 1

        let target = !current
        isFavorite = target

        Task {
            do {
                if target {
                    try await store.save(bookmark)
                } else {
                    try await store.remove(bookmark)
                }
            } catch {
                isFavorite = current
                AppLogger.warning(
                    "书签收藏写入失败，errorType=\(type(of: error))",
                    category: "Bookmarks",
                )
                ToastCenter.shared.show(
                    target ? "收藏失败，请稍后重试" : "取消收藏失败，请稍后重试",
                    type: .error,
                )
            }
        }
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

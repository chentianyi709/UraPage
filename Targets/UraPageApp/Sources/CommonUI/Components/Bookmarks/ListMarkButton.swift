import SwiftUI

/// 列表页右上角的收藏／关注按钮：按维度选择具体按钮，两个列表页共用。
///
/// 作者维度渲染 `FollowingButton`（关注库），其余渲染 `BookmarkButton`（书签库）；
/// 只在这里做「是作者还是标签」的选择，两种按钮的存储、文案与失败提示仍各自独立。
struct ListMarkButton: View {
    /// 当前列表代表的那一条书签。
    let bookmark: Bookmark

    var body: some View {
        if let following = Following(bookmark: bookmark) {
            FollowingButton(following: following)
        } else {
            BookmarkButton(bookmark: bookmark)
        }
    }
}

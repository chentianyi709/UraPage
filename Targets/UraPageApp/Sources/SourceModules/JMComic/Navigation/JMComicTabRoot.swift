import SwiftUI

/// 禁漫各 Tab 的根页面内容。
///
/// 作为 `SourceTabContainer` 泛型实参的稳定外壳：各 Tab 的页面类型只在本文件内变化，
/// 外层 `TabView`／`Tab` 的实例化不会随页面改动改变布局。此前页面类型变化后增量构建
/// 会让外层泛型用旧布局读脏指针而崩溃（`swift_retain`），这里把变化面收进本文件。
/// **不要再给这个外壳加存储属性**：它的布局就是外层泛型的实参，加字段等于又改了外层泛型的布局。
struct JMComicTabRootContent: View {
    /// 本源体验状态；分类／更新页的筛选交接需要它。
    let experience: JMComicExperience

    let tab: JMComicTab

    var body: some View {
        switch tab {
        case .home:
            JMComicHomeView()

        case .latest:
            JMComicLatestView()

        case .categories:
            JMComicCategoriesView()
                .environment(
                    \.sourceListFilterRequest,
                    experience.listFilterHandoff.pending.map { pending in
                        JMComicListPages.categoryFilterRequest(
                            slug: pending.value,
                            token: pending.token,
                        )
                    },
                )

        case .library:
            // 书架是所有来源共用的通用页面（顶层 Features/Library）。
            LibraryView()

        case .search:
            JMComicSearchView()
        }
    }
}

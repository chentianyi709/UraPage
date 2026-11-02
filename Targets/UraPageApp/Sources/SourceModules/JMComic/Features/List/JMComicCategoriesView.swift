import SwiftUI

/// 禁漫分类 Tab；首页的外部筛选由公共列表状态一次应用。
struct JMComicCategoriesView: View {
    @Environment(\.jmComicServices) private var services
    @Environment(\.appShell) private var shell

    var body: some View {
        SourceListPage(
            title: "分类",
            services: services,
            descriptor: { JMComicListPages.categories(services: $0) },
            coverOverlay: { JMComicUpdateOverlay(item: $0) },
        ) { item in
            shell.navigator.push(JMComicRoute.detail(item.identity))
        }
    }
}

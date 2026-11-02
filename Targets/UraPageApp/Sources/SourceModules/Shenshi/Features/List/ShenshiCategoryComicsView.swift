import SwiftUI

/// 绅士详情分类的分页作品列表；独立于「最近更新」Tab 的筛选与滚动状态。
struct ShenshiCategoryComicsView: View {
    @Environment(\.shenshiServices) private var services
    @Environment(\.appShell) private var shell

    let category: ShenshiLatestCategory

    var body: some View {
        SourceListPage(
            title: category.title,
            titleStyle: .inline,
            services: services,
            bookmark: Bookmark(
                sourceID: .shenshi,
                kind: .category,
                displayName: category.title,
                value: category,
            ),
            descriptor: { ShenshiListPages.category(services: $0, category: category) },
        ) { item in
            shell.navigator.push(ShenshiRoute.detail(item.identity))
        }
    }
}

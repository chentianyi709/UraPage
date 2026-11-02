import SwiftUI

/// 哔咔详情分类的可排序作品列表；与分类 Tab 的状态互不影响。
struct BikaCategoryComicsView: View {
    @Environment(\.bikaServices) private var services
    @Environment(\.appShell) private var shell

    let category: BikaComicCategory

    var body: some View {
        SourceListPage(
            title: category.title,
            titleStyle: .inline,
            services: services,
            bookmark: Bookmark(
                sourceID: .bika,
                kind: .category,
                displayName: category.title,
                value: category,
            ),
            descriptor: { BikaListPages.filtered(services: $0, filter: .category(category)) },
        ) { item in
            shell.navigator.push(BikaRoute.detail(item.identity))
        }
    }
}

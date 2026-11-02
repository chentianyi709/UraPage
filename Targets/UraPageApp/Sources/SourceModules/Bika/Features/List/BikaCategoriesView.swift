import SwiftUI

/// 哔咔分类 Tab：本页持有筛选状态、标题和漫画导航。
struct BikaCategoriesView: View {
    @Environment(\.bikaServices) private var services
    @Environment(\.appShell) private var shell

    var body: some View {
        SourceListPage(
            title: "分类",
            services: services,
            descriptor: { BikaListPages.categories(services: $0) },
        ) { item in
            shell.navigator.push(BikaRoute.detail(item.identity))
        }
    }
}

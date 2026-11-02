import SwiftUI

/// 哔咔作者、汉化组或上传者的作品列表。
struct BikaContributorComicsView: View {
    @Environment(\.bikaServices) private var services
    @Environment(\.appShell) private var shell

    let contributor: BikaComicContributor

    var body: some View {
        SourceListPage(
            title: contributor.name,
            titleStyle: .inline,
            services: services,
            bookmark: Bookmark(
                sourceID: .bika,
                kind: .author,
                displayName: contributor.name,
                value: contributor,
            ),
            descriptor: { BikaListPages.filtered(services: $0, filter: .contributor(contributor)) },
        ) { item in
            shell.navigator.push(BikaRoute.detail(item.identity))
        }
    }
}

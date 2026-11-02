import SwiftUI

/// 哔咔上传者作品页；上传者身份来自路由，服务由本源环境提供。
struct BikaUploaderComicsView: View {
    @Environment(\.bikaServices) private var services
    @Environment(\.appShell) private var shell

    let id: String
    let name: String

    var body: some View {
        SourceListPage(
            title: name,
            titleStyle: .inline,
            services: services,
            bookmark: Bookmark(
                sourceID: .bika,
                kind: .author,
                displayName: name,
                value: BikaComicContributor.uploader(id: id, name: name),
            ),
            descriptor: { BikaListPages.uploader(services: $0, id: id, name: name) },
        ) { item in
            shell.navigator.push(BikaRoute.detail(item.identity))
        }
    }
}

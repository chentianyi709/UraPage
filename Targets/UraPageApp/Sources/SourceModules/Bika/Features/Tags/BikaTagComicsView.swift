import Foundation
import SwiftUI

/// 哔咔详情标签对应的可排序作品列表。
struct BikaTagComicsView: View {
    @Environment(\.bikaServices) private var services
    @Environment(\.appShell) private var shell

    let tag: String

    var body: some View {
        SourceListPage(
            title: tag.trimmingCharacters(in: .whitespacesAndNewlines),
            titleStyle: .inline,
            services: services,
            bookmark: Bookmark(
                sourceID: .bika,
                kind: .tag,
                displayName: tag.trimmingCharacters(in: .whitespacesAndNewlines),
                value: tag,
            ),
            descriptor: { BikaListPages.filtered(services: $0, filter: .tag(tag)) },
        ) { item in
            shell.navigator.push(BikaRoute.detail(item.identity))
        }
    }
}

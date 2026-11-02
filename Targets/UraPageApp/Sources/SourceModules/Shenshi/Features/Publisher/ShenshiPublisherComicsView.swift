import SwiftUI

/// 展示发布者的投稿列表；游标分页与加载状态复用公共列表组件。
struct ShenshiPublisherComicsView: View {
    @Environment(\.shenshiServices) private var services
    @Environment(\.appShell) private var shell

    let publisher: ShenshiComicPublisher

    var body: some View {
        SourceListPage(
            title: publisher.name,
            titleStyle: .inline,
            services: services,
            bookmark: Bookmark(
                sourceID: .shenshi,
                kind: .author,
                displayName: publisher.name,
                value: publisher,
            ),
            descriptor: { ShenshiListPages.publisher(services: $0, publisher: publisher) },
        ) { item in
            shell.navigator.push(ShenshiRoute.detail(item.identity))
        }
    }
}

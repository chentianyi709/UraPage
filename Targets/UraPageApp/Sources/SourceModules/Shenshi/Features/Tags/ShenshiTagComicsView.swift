import SwiftUI

/// 绅士详情标签的分页作品列表；第 1 页使用网页提供的精确路径，后续页按页码改写该路径续载。
struct ShenshiTagComicsView: View {
    @Environment(\.shenshiServices) private var services
    @Environment(\.appShell) private var shell

    let tag: ShenshiComicTag

    var body: some View {
        SourceListPage(
            title: tag.name,
            titleStyle: .inline,
            services: services,
            bookmark: Bookmark(
                sourceID: .shenshi,
                kind: .tag,
                displayName: tag.name,
                value: tag,
            ),
            descriptor: { ShenshiListPages.tag(services: $0, tag: tag) },
        ) { item in
            shell.navigator.push(ShenshiRoute.detail(item.identity))
        }
    }
}

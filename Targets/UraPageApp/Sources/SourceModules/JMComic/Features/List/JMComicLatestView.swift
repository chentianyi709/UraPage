import SwiftUI

/// 禁漫最新漫画 Tab。
struct JMComicLatestView: View {
    @Environment(\.jmComicServices) private var services
    @Environment(\.appShell) private var shell

    var body: some View {
        SourceListPage(
            title: "最新漫画",
            services: services,
            descriptor: { JMComicListPages.latest(services: $0) },
            coverOverlay: { JMComicUpdateOverlay(item: $0) },
        ) { item in
            shell.navigator.push(JMComicRoute.detail(item.identity))
        }
    }
}

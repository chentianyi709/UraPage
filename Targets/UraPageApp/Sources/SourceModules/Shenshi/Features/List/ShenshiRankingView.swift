import SwiftUI

/// 绅士排行榜 Tab。
struct ShenshiRankingView: View {
    @Environment(\.shenshiServices) private var services
    @Environment(\.appShell) private var shell

    var body: some View {
        SourceListPage(
            title: "排行榜",
            services: services,
            descriptor: { ShenshiListPages.ranking(services: $0) },
        ) { item in
            shell.navigator.push(ShenshiRoute.detail(item.identity))
        }
    }
}

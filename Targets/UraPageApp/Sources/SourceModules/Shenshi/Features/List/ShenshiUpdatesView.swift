import SwiftUI

/// 绅士最近更新 Tab。
struct ShenshiUpdatesView: View {
    @Environment(\.shenshiServices) private var services
    @Environment(\.appShell) private var shell

    var body: some View {
        SourceListPage(
            title: "最近更新",
            services: services,
            descriptor: { ShenshiListPages.updates(services: $0) },
        ) { item in
            shell.navigator.push(ShenshiRoute.detail(item.identity))
        }
    }
}

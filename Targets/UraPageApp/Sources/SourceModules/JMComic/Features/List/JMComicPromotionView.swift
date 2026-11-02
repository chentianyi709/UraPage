import SwiftUI

/// 禁漫首页推广分区的漫画列表。
struct JMComicPromotionView: View {
    @Environment(\.jmComicServices) private var services
    @Environment(\.appShell) private var shell

    let sectionID: String
    let sectionTitle: String

    var body: some View {
        SourceListPage(
            title: sectionTitle,
            titleStyle: .inline,
            services: services,
            descriptor: { JMComicListPages.promotion(services: $0, sectionID: sectionID) },
            coverOverlay: { JMComicUpdateOverlay(item: $0) },
        ) { item in
            shell.navigator.push(JMComicRoute.detail(item.identity))
        }
    }
}

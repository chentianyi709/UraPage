import SwiftUI

/// 禁漫周刊页；标题随日期筛选变化，页面保留自身查询状态。
struct JMComicWeeklyView: View {
    @Environment(\.jmComicServices) private var services
    @Environment(\.appShell) private var shell

    let sectionTitle: String

    var body: some View {
        SourceListPage(
            titleStyle: .inline,
            services: services,
            descriptor: { JMComicListPages.weekly(services: $0) },
            title: { query in
                guard let date = query?.date else {
                    return sectionTitle
                }

                return date == .completed ? "已完结漫画" : "\(date.displayTitle) \(sectionTitle)"
            },
            coverOverlay: { JMComicUpdateOverlay(item: $0) },
        ) { item in
            shell.navigator.push(JMComicRoute.detail(item.identity))
        }
    }
}

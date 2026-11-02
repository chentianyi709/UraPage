import SwiftUI

/// 禁漫 push 目标的页面容器。
///
/// 周刊与推广由各自页面承载，列表内容共用组件；详情由本源详情页加载并呈现公共内容。
struct JMComicDestinationView: View {
    let route: JMComicRoute

    var body: some View {
        switch route {
        case let .detail(route):
            // 在线／离线详情共用公共内容视图，页面状态在详情页内创建。
            JMComicDetailView(identity: route.identity, mode: route.mode)

        case let .reader(input):
            JMComicReaderView(input: input)

        case let .weekly(sectionTitle):
            JMComicWeeklyView(sectionTitle: sectionTitle)

        case let .promotion(sectionID, sectionTitle):
            JMComicPromotionView(sectionID: sectionID, sectionTitle: sectionTitle)

        case let .queryComics(query):
            JMComicQueryComicsView(query: query, bookmarkKind: .author)

        case let .tagComics(tag):
            JMComicQueryComicsView(query: tag, searchType: .tag, bookmarkKind: .tag)
        }
    }
}

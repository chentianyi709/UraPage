import SwiftUI

/// 绅士 push 目标的页面容器。
///
/// 详情与发布者投稿路由分别由本源页面处理。
struct ShenshiDestinationView: View {
    let route: ShenshiRoute

    var body: some View {
        switch route {
        case let .detail(route):
            // 在线／离线详情共用公共内容视图，页面状态在详情页内创建。
            ShenshiComicDetailView(identity: route.identity, mode: route.mode)

        case let .reader(input):
            ShenshiReaderView(input: input)

        case let .publisherComics(publisher):
            ShenshiPublisherComicsView(publisher: publisher)

        case let .tagComics(tag):
            ShenshiTagComicsView(tag: tag)

        case let .categoryComics(category):
            ShenshiCategoryComicsView(category: category)
        }
    }
}

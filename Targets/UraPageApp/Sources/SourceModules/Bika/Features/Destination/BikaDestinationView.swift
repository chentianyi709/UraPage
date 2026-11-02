import SwiftUI

/// 哔咔 push 目标的页面容器。
///
/// 上传者与贡献者作品由各自页面承载；详情由本源详情页加载并呈现公共内容。
struct BikaDestinationView: View {
    let route: BikaRoute

    var body: some View {
        switch route {
        case let .detail(route):
            // 在线／离线详情共用公共内容视图，页面状态在详情页内创建。
            BikaComicDetailView(identity: route.identity, mode: route.mode)

        case let .reader(input):
            BikaReaderView(input: input)

        case let .uploaderComics(id, name):
            // 上传者作品：普通分页列表页，标题用上传者展示名。
            BikaUploaderComicsView(id: id, name: name)

        case let .contributorComics(contributor):
            BikaContributorComicsView(contributor: contributor)

        case let .tagComics(tag):
            BikaTagComicsView(tag: tag)

        case let .categoryComics(category):
            BikaCategoryComicsView(category: category)
        }
    }
}

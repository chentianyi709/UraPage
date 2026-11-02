import Foundation
import SwiftUI

/// 绅士详情页：在线详情与下载快照共用公共详情骨架。
///
/// 绅士网页只有一个章节；发布者、分类与标签作为详情导航值随下载快照一起保存。
struct ShenshiComicDetailView: View {
    @Environment(\.appShell) private var shell
    @Environment(\.shenshiServices) private var services

    let identity: ComicIdentity
    let mode: ComicContentMode

    var body: some View {
        SourceComicDetailPage(
            identity: identity,
            mode: mode,
            loadPresentation: { identity in
                try await Self.loadPresentation(services: services, identity: identity)
            },
            decodeNavigation: { snapshot in
                try snapshot.sourceNavigation(as: ShenshiDownloadedDetailNavigation.self)
            },
            onSelectAuthor: { _, navigation, _, _ in
                if let publisher = navigation?.publisher {
                    shell.navigator.push(ShenshiRoute.publisherComics(publisher))
                }
            },
            onSelectCategory: { _, navigation, _ in
                if let category = navigation?.category {
                    shell.navigator.push(ShenshiRoute.categoryComics(category))
                }
            },
            onSelectTag: { _, navigation, name in
                guard let tag = navigation?.comicTags.first(where: { $0.name == name }) else { return }

                shell.navigator.push(ShenshiRoute.tagComics(tag))
            },
            copyContentProvider: {
                let url = try await services.detailPageURL(comicID: identity.comicID)
                return ComicDetailCopyResult(
                    content: url.absoluteString,
                    successMessage: "已复制作品链接",
                )
            },
            onOpenReader: { input in
                shell.navigator.push(ShenshiRoute.reader(input))
            },
            logCategory: "Shenshi.Detail",
            related: { presentation in
                if mode == .online {
                    ComicDetailRelatedContent(comics: presentation.relatedComics) { relatedIdentity in
                        shell.navigator.push(ShenshiRoute.detail(relatedIdentity))
                    }
                } else {
                    EmptyView()
                }
            },
        )
    }

    /// 在线详情映射：唯一章节同时用于阅读、下载与章节弹窗。
    private static func loadPresentation(
        services: ShenshiServices,
        identity: ComicIdentity,
    ) async throws -> ComicDetailPresentation {
        let sourceDetail = try await services.detail(for: identity)
        let chapterIdentity = ChapterIdentity(
            comic: sourceDetail.identity,
            chapterID: sourceDetail.identity.comicID,
        )
        let navigation = ShenshiDownloadedDetailNavigation(
            publisher: sourceDetail.publisher,
            category: sourceDetail.category,
            comicTags: sourceDetail.comicTags,
        )
        let snapshot = try DownloadedComicDetailSnapshot(
            detail: sourceDetail,
            categories: sourceDetail.category.map { [$0.title] } ?? [],
            sourceNavigationData: JSONEncoder().encode(navigation),
            showsChaptersButton: false,
        )
        let chapter = DownloadChapterCandidate(
            identity: chapterIdentity,
            title: sourceDetail.title,
            order: 0,
        )
        return ComicDetailPresentation(
            detail: snapshot,
            readerChapters: [chapter],
            downloadCandidates: [chapter],
            chapterPickerChapters: [chapter],
            relatedComics: sourceDetail.relatedComics,
        )
    }
}

private struct ShenshiDownloadedDetailNavigation: Codable, Sendable {
    let publisher: ShenshiComicPublisher?
    let category: ShenshiLatestCategory?
    let comicTags: [ShenshiComicTag]
}

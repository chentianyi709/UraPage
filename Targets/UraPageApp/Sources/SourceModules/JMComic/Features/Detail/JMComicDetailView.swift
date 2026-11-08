import Foundation
import SwiftUI

/// 禁漫详情页：在线详情与下载快照共用公共详情骨架。
struct JMComicDetailView: View {
    @Environment(\.appShell) private var shell
    @Environment(\.jmComicServices) private var services

    let identity: ComicIdentity
    let mode: ComicContentMode

    var body: some View {
        SourceComicDetailPage(
            identity: identity,
            mode: mode,
            loadPresentation: { identity in
                try await Self.loadPresentation(services: services, identity: identity)
            },
            decodeNavigation: { _ in EmptyDetailNavigation() },
            onSelectAuthor: { _, _, _, authorName in
                let query = authorName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !query.isEmpty else { return }

                shell.navigator.push(JMComicRoute.queryComics(query: query))
            },
            onSelectTag: { _, _, kind, name in
                guard kind == .tag else { return }

                shell.navigator.push(JMComicRoute.tagComics(name))
            },
            copyContentProvider: { [identity] in
                ComicDetailCopyResult(
                    content: identity.comicID,
                    successMessage: "已复制作品 ID",
                )
            },
            likeAction: ComicDetailLikeAction(allowsUnliking: false) { identity in
                let result = try await services.likeComic(identity)
                let message = result.message.isEmpty ? nil : result.message
                return result.succeeded
                    ? .liked(message: message)
                    : .rejected(message: message)
            },
            onOpenReader: { input in
                shell.navigator.push(JMComicRoute.reader(input))
            },
            logCategory: "JM.Detail",
            related: { presentation in
                if mode == .online {
                    ComicDetailRelatedContent(comics: presentation.relatedComics) { relatedIdentity in
                        shell.navigator.push(JMComicRoute.detail(relatedIdentity))
                    }
                } else {
                    EmptyView()
                }
            },
        )
    }

    /// 在线详情映射：阅读章节与真实目录可能不同（单话合成章节不进入章节弹窗）。
    private static func loadPresentation(
        services: JMComicServices,
        identity: ComicIdentity,
    ) async throws -> ComicDetailPresentation {
        let sourceDetail = try await services.detail(for: identity)
        let snapshot = DownloadedComicDetailSnapshot(
            detail: sourceDetail,
            sourceNavigationData: Data(),
            showsChaptersButton: sourceDetail.showsChaptersButton,
        )
        let readerChapters = sourceDetail.readerChapters.enumerated().map {
            DownloadChapterCandidate(
                identity: $0.element.identity,
                title: $0.element.title,
                order: $0.offset,
            )
        }
        let chapterPickerChapters = sourceDetail.chapters.enumerated().map {
            DownloadChapterCandidate(
                identity: $0.element.identity,
                title: $0.element.title,
                order: $0.offset,
            )
        }
        return ComicDetailPresentation(
            detail: snapshot,
            readerChapters: readerChapters,
            downloadCandidates: readerChapters,
            chapterPickerChapters: chapterPickerChapters,
            relatedComics: sourceDetail.relatedComics,
            isLiked: sourceDetail.isLiked,
        )
    }
}

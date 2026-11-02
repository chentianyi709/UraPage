import Foundation
import SwiftUI

/// 哔咔详情页：把本源详情映射成公共展示状态，其余加载、进度、底栏与下载接线由公共页承担。
///
/// 作者、分类与标签可进入对应作品列表；推荐区单独加载，失败不阻塞详情主内容。
/// 详情封面按产品规则固定原画，不受「非阅读图片清晰度」影响。
struct BikaComicDetailView: View {
    @Environment(\.appShell) private var shell
    @Environment(\.bikaServices) private var services

    /// 推荐单独加载，失败不阻塞详情主内容。
    @State private var recommendationsModel: SourceValueLoadModel<[ComicListItem]>?

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
                try snapshot.sourceNavigation(as: BikaDownloadedDetailNavigation.self)
            },
            onSelectAuthor: { _, navigation, index, _ in
                guard let navigation,
                      navigation.contributors.indices.contains(index)
                else { return }

                shell.navigator.push(
                    BikaRoute.contributorComics(navigation.contributors[index]),
                )
            },
            onSelectCategory: { _, navigation, name in
                // 胶囊只提供展示名称；路由携带当前详情给出的分类值。
                guard let category = navigation?.categories.first(where: {
                    $0.title.trimmingCharacters(in: .whitespacesAndNewlines) == name
                }) else { return }

                shell.navigator.push(BikaRoute.categoryComics(category))
            },
            onSelectTag: { presentation, _, name in
                // 公共胶囊会清理展示空白；请求仍使用详情响应的原始标签值。
                guard let tag = presentation.detail.tags.first(where: {
                    $0.trimmingCharacters(in: .whitespacesAndNewlines) == name
                }) else { return }

                shell.navigator.push(BikaRoute.tagComics(tag))
            },
            copyContentProvider: nil,
            likeAction: ComicDetailLikeAction(allowsUnliking: true) { identity in
                switch try await services.toggleComicLike(identity) {
                case .liked:
                    .liked(message: nil)

                case .notLiked:
                    .unliked(message: nil)
                }
            },
            onOpenReader: { input in
                shell.navigator.push(BikaRoute.reader(input))
            },
            onPresentationLoaded: { presentation in
                guard mode == .online else { return }

                Task {
                    do {
                        try await services.recordRecommendationTransition(to: presentation.detail.identity)
                    } catch is CancellationError {
                        return
                    } catch {
                        // Services 已记录脱敏错误；上报失败不影响详情内容。
                        AppLogger.warning("详情已展示，推荐跳转记录未完成", category: "Bika.Recommendations")
                    }
                }
            },
            logCategory: "Bika.Detail",
            related: { presentation in
                if mode == .online, let recommendationsModel {
                    BikaComicRecommendationsSection(model: recommendationsModel) { identity in
                        shell.navigator.push(BikaRoute.detail(identity))
                    }
                } else {
                    EmptyView()
                }
            },
        )
        .task {
            prepareRecommendationsIfNeeded()
            recommendationsModel?.loadIfNeeded()
        }
    }

    /// 首次展示时创建推荐状态 owner；离线详情不请求推荐。
    private func prepareRecommendationsIfNeeded() {
        guard mode == .online, recommendationsModel == nil else {
            return
        }

        let services = services
        let identity = identity
        recommendationsModel = SourceValueLoadModel(logCategory: "Bika.Recommendations") {
            try await services.recommendations(for: identity)
        }
    }

    /// 在线详情映射：详情快照、导航值、阅读／下载章节都在这里一次完成。
    private static func loadPresentation(
        services: BikaServices,
        identity: ComicIdentity,
    ) async throws -> ComicDetailPresentation {
        let sourceDetail = try await services.detail(for: identity)
        let navigation = BikaDownloadedDetailNavigation(
            contributors: sourceDetail.contributors,
            categories: sourceDetail.categories,
        )
        let snapshot = try DownloadedComicDetailSnapshot(
            detail: sourceDetail,
            categories: sourceDetail.categories.map(\.title),
            sourceNavigationData: JSONEncoder().encode(navigation),
            showsChaptersButton: sourceDetail.showsChaptersButton,
        )
        let chapters = sourceDetail.chapters.enumerated().map {
            DownloadChapterCandidate(
                identity: $0.element.identity,
                title: $0.element.title,
                order: $0.offset,
            )
        }
        return ComicDetailPresentation(
            detail: snapshot,
            readerChapters: chapters,
            downloadCandidates: chapters,
            chapterPickerChapters: chapters,
            isLiked: sourceDetail.isLiked,
        )
    }
}

private struct BikaDownloadedDetailNavigation: Codable, Sendable {
    let contributors: [BikaComicContributor]
    let categories: [BikaComicCategory]
}

/// 推荐独立加载：加载时显示卡片骨架，失败时隐藏分区，不影响主详情。
private struct BikaComicRecommendationsSection: View {
    let model: SourceValueLoadModel<[ComicListItem]>
    let onSelect: (ComicIdentity) -> Void

    var body: some View {
        switch model.loadState {
        case .idle, .loading:
            ComicDetailSection(title: "相关推荐", systemImage: "sparkles") {
                ComicDetailRelatedSkeletonGrid()
                    .skeletonLoadingEffect()
            }

        case .loaded:
            ComicDetailRelatedContent(comics: model.items, onSelect: onSelect)

        case .failed:
            // SourceValueLoadModel 已按 Bika.Recommendations 分类记录失败日志。
            EmptyView()
        }
    }
}

import SwiftUI

/// 哔咔首页内容：同一纵向滚动容器里组合「随机本子」与「最近更新」两个分区。
///
/// 两个分区来自不同接口，**各自加载、互不等待**：谁先完成谁先显示，
/// 另一个还在加载时保留自己的骨架；单个分区失败时在该分区位置就地提示并重试。
/// 随机本子是两行横向卡片，最近更新是三列卡片并可续载；分区标题都没有箭头（本源首页没有跨页跳转语义）。
struct BikaHomeContentView: View {
    /// 随机本子的数据阶段（加载完成时直接带卡片）。
    let randomState: InitialValueLoadState<[ComicListItem]>

    /// 最近更新的数据阶段。
    let recentlyUpdatedState: InitialLoadState<SourceLoadDisplayError>

    /// 最近更新已加载的卡片；未加载完成时为空。
    let recentlyUpdatedComics: [ComicListItem]

    let isLoadingMore: Bool
    let canLoadMore: Bool
    let loadMoreErrorMessage: String?

    let onSelectComic: (ComicListItem) -> Void

    /// 分区加载失败后的就地重试（只重发失败的分区）。
    let onRetryFailedSection: () -> Void

    let onLoadMore: @MainActor () -> Void
    let onRetryLoadMore: @MainActor () -> Void

    var body: some View {
        GeometryReader { proxy in
            let itemWidth = ComicGridMetrics.itemWidth(for: proxy.size.width)

            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 24) {
                    randomSection
                    recentlyUpdatedSection(itemWidth: itemWidth)
                }
                .padding(.vertical, ComicGridMetrics.verticalPadding)
            }
            .scrollToTopButton()
            .onApproachingBottom(prefetchScreens: 1.6, action: onLoadMore)
        }
    }

    // MARK: - 随机本子

    @ContentBuilder
    private var randomSection: some View {
        switch randomState {
        case .idle, .loading:
            ComicShelfSkeletonSection(showsDisclosureIndicator: false)

        case let .loaded(comics):
            ComicShelfSection(
                title: "随机本子",
                items: comics,
                emptyText: "暂无随机本子",
                onSelectComic: onSelectComic,
            )

        case let .failed(error):
            SectionLoadFailureView(title: "随机本子", message: error.message, onRetry: onRetryFailedSection)
        }
    }

    // MARK: - 最近更新

    @ContentBuilder
    private func recentlyUpdatedSection(itemWidth: CGFloat) -> some View {
        switch recentlyUpdatedState {
        case .idle, .loading:
            ComicSectionSkeleton(showsDisclosureIndicator: false) {
                ComicCardSkeletonGridView(itemWidth: itemWidth, cardCount: 9)
            }
            .skeletonLoadingEffect()

        case .loaded:
            recentlyUpdatedGrid(itemWidth: itemWidth)

        case let .failed(error):
            SectionLoadFailureView(title: "最近更新", message: error.message, onRetry: onRetryFailedSection)
        }
    }

    /// 最近更新分区：标题 + 三列卡片 + 分页尾部。
    private func recentlyUpdatedGrid(itemWidth: CGFloat) -> some View {
        ComicSection {
            ComicSectionHeader(title: "最近更新", showsDisclosureIndicator: false)
        } content: {
            if recentlyUpdatedComics.isEmpty {
                ComicSectionEmptyText(text: "暂无最近更新")
            } else {
                LazyVGrid(
                    columns: ComicGridMetrics.columns(itemWidth: itemWidth),
                    alignment: .center,
                    spacing: ComicGridMetrics.rowSpacing,
                ) {
                    ForEach(recentlyUpdatedComics) { comic in
                        ComicCardView(item: comic, itemWidth: itemWidth) { selected in
                            onSelectComic(selected)
                        }
                    }
                }
                .padding(.horizontal, ComicGridMetrics.horizontalPadding)

                PaginationFooter(
                    isLoadingMore: isLoadingMore,
                    canLoadMore: canLoadMore,
                    loadMoreErrorMessage: loadMoreErrorMessage,
                    onRetryLoadMore: onRetryLoadMore,
                )
                .padding(.horizontal, ComicGridMetrics.horizontalPadding)
            }
        }
    }
}

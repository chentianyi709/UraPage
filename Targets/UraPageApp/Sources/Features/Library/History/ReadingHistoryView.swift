import SwiftUI

/// 书架中的跨来源阅读记录；点卡片进入作品所属来源详情。
struct ReadingHistoryView: View {
    @Environment(\.appShell) private var shell
    @Environment(\.readingHistoryStore) private var store
    @Environment(\.sourceRuntimeCatalog) private var catalog

    @State private var model: ReadingHistoryViewModel?
    @State private var imageServices: [ComicSourceID: any ComicImageService] = [:]
    @State private var pendingDelete: ReadingHistoryCard?
    @State private var gridContainerSize: CGSize = .zero

    let isActive: Bool

    var body: some View {
        InitialLoadView(
            model: model,
            initialState: { $0.loadState },
            isEmpty: { $0.items.isEmpty },
        ) {
            ComicGridSkeletonView()
        } empty: {
            EmptyStateView(title: "暂无阅读记录", message: "阅读漫画后会在这里显示最近进度")
                .frame(maxHeight: .infinity)
        } failure: { model, error in
            LoadErrorView(title: "阅读记录加载失败", message: error.message, onRetry: model.refresh)
                .frame(maxHeight: .infinity)
        } content: { model in
            historyGrid(model)
        }
        .task(id: isActive) {
            // 观看历史没有变更流：首次激活创建模型，每次回到该分区都重读（新记录与保留期清理都在这里生效）。
            guard isActive else { return }

            if model == nil {
                imageServices = Dictionary(uniqueKeysWithValues: ComicSourceID.allCases.map {
                    ($0, catalog.runtime(for: $0).makeBrowsingImages())
                })
                model = ReadingHistoryViewModel(
                    store: store,
                    sourceNames: Dictionary(uniqueKeysWithValues: shell.sourceDescriptors.map {
                        ($0.sourceID, $0.displayName)
                    }),
                )
            }
            model?.refresh()
        }
        .alert(
            "删除观看记录？",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: {
                    if !$0 {
                        pendingDelete = nil
                    }
                },
            ),
            presenting: pendingDelete,
        ) { card in
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) {
                deleteHistory(card)
            }
        } message: { card in
            Text("将删除《\(card.comic.title)》的观看记录与继续阅读进度，此操作不可恢复。")
        }
    }

    private func historyGrid(_ model: ReadingHistoryViewModel) -> some View {
        let descriptors = Dictionary(uniqueKeysWithValues: shell.sourceDescriptors.map {
            ($0.sourceID, $0)
        })
        return ComicGridContent(
            items: model.items,
            onSelect: openComic,
            isLoadingMore: model.isLoadingMore,
            canLoadMore: model.canLoadMore,
            loadMoreErrorMessage: model.loadMoreError,
            onLoadMore: model.loadMoreIfNeeded,
            onRetryLoadMore: model.retryLoadMore,
        ) { item, itemWidth, onSelect in
            historyCard(
                item,
                itemWidth: itemWidth,
                containerSize: gridContainerSize,
                sourceLogo: descriptors[item.comic.identity.sourceID]?.logo,
                onSelect: onSelect,
            )
        }
        .onGeometryChange(for: CGSize.self) { proxy in
            proxy.size
        } action: { size in
            gridContainerSize = size
        }
    }

    private func historyCard(
        _ item: ReadingHistoryCard,
        itemWidth: CGFloat,
        containerSize: CGSize,
        sourceLogo: SourceLogo?,
        onSelect: ((ReadingHistoryCard) -> Void)?,
    ) -> some View {
        ComicCardView(
            item: item.comic,
            itemWidth: itemWidth,
            onSelect: onSelect.map { select in { _ in select(item) } },
        ) {
            ZStack(alignment: .topLeading) {
                if let sourceLogo {
                    SourceLogoView(sourceLogo, size: 14)
                        .padding(6)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .allowsHitTesting(false)
        }
        .comicCardContextMenu(
            item: item.comic,
            containerSize: containerSize,
        ) {
            Button("删除", systemImage: "trash", role: .destructive) {
                pendingDelete = item
            }
        }
        .environment(\.browsingImageServiceStorage, imageService(for: item.comic.identity.sourceID))
    }

    /// 模型创建前已为全部来源建立图片服务；缺失代表页面装配错误，不能回退到当前来源。
    private func imageService(for sourceID: ComicSourceID) -> any ComicImageService {
        guard let service = imageServices[sourceID] else {
            preconditionFailure("阅读记录缺少已注册来源的图片服务")
        }

        return service
    }

    private func openComic(_ item: ReadingHistoryCard) {
        do {
            try shell.navigator.open(.detail(
                item.progressIdentity.comic,
                mode: item.progressIdentity.contentMode,
            ))
        } catch {
            AppLogger.error(
                "阅读记录跳转失败，errorType=\(String(reflecting: type(of: error)))",
                category: "Library.History",
            )
            ToastCenter.shared.show("无法打开这部漫画", type: .error)
        }
    }

    /// 确认后删除该作品的全部阅读记录；失败提示可重试，成功提示已删除。
    private func deleteHistory(_ card: ReadingHistoryCard) {
        guard let model else { return }

        Task {
            if await model.delete(card) {
                ToastCenter.shared.show("已删除《\(card.comic.title)》的观看记录", type: .success)
            } else {
                ToastCenter.shared.show("删除失败，请稍后重试", type: .error)
            }
        }
    }
}

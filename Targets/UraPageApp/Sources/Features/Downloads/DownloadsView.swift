import SwiftUI

/// 书架中的跨来源「下载记录」：本地封面盖蒙版显示下载进度。
/// 点击按状态分流——未完成时暂停／继续／重试，已完成才打开同一详情页的离线数据。
struct DownloadsView: View {
    @Environment(\.appShell) private var shell
    @Environment(\.downloadManager) private var manager

    @State private var model: DownloadsViewModel?
    @State private var exportModel: DownloadsExportModel?
    @State private var pendingDelete: DownloadedComicSummary?
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
            EmptyStateView(title: "暂无下载", message: "在详情页下载作品后会在这里显示")
                .frame(maxHeight: .infinity)
        } failure: { model, error in
            LoadErrorView(title: "下载记录加载失败", message: error.message, onRetry: model.refresh)
                .frame(maxHeight: .infinity)
        } content: { model in
            downloadGrid(model)
        }
        .task(id: isActive) {
            // 只在首次激活时创建并加载；页面常驻后切回不重读。
            // 下载期间的状态变化由 start() 订阅的变更流持续推送，不需要重新查库。
            guard isActive, model == nil else { return }

            let model = DownloadsViewModel(manager: manager)
            self.model = model
            exportModel = DownloadsExportModel(manager: manager)
            model.start()
            model.refresh()
        }
        .sheet(
            isPresented: Binding(
                get: { exportModel?.archive != nil },
                set: {
                    if !$0 {
                        exportModel?.finishSharing()
                    }
                },
            ),
        ) {
            if let archive = exportModel?.archive {
                SystemShareSheet(url: archive.url) { completed, activityIdentifier in
                    exportModel?.finishSharing()
                    showSaveResult(completed: completed, activityIdentifier: activityIdentifier)
                }
            }
        }
        .alert(
            "删除下载记录？",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: {
                    if !$0 {
                        pendingDelete = nil
                    }
                },
            ),
            presenting: pendingDelete,
        ) { summary in
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) {
                deleteDownload(summary)
            }
        } message: { summary in
            Text("将删除《\(summary.title)》的下载记录，并移除已下载的章节图片与封面文件，此操作不可恢复。")
        }
    }

    private func downloadGrid(_ model: DownloadsViewModel) -> some View {
        let descriptors = Dictionary(uniqueKeysWithValues: shell.sourceDescriptors.map {
            ($0.sourceID, $0)
        })
        let summaries = Dictionary(uniqueKeysWithValues: model.items.map {
            ($0.identity, $0)
        })
        // 这里只读「哪个作品正在导出」：开始/结束各重建一次网格；百分比进度由卡片内的
        // `ExportProgressBadge` 自己订阅，不随每一档百分比重算整个网格。
        let exportingComic = exportModel?.exportingIdentity
        return ComicGridContent(
            items: model.items.map(makeCard),
            onSelect: { item in handleSelect(item, summaries: summaries, model: model) },
            isLoadingMore: model.isLoadingMore,
            canLoadMore: model.canLoadMore,
            loadMoreErrorMessage: model.loadMoreError,
            onLoadMore: model.loadMoreIfNeeded,
            onRetryLoadMore: model.retryLoadMore,
            cardContent: { item, itemWidth, onSelect in
                ComicCardView(item: item, itemWidth: itemWidth, onSelect: onSelect) {
                    coverOverlay(
                        summary: summaries[item.identity],
                        identity: item.identity,
                        descriptors: descriptors,
                    )
                }
                .comicCardContextMenu(
                    item: item,
                    containerSize: gridContainerSize,
                ) {
                    if summaries[item.identity]?.state == .completed {
                        Button("导出", systemImage: "square.and.arrow.up") {
                            beginExport(item.identity)
                        }
                        // 导出不是破坏性操作：图标用默认前景色，不跟随 App 的品牌色。
                        .tint(.primary)
                        // 一次只导出一个作品：导出期间不给第二个入口，避免点了没有反应。
                        .disabled(exportingComic != nil)
                    }
                    Button("删除", systemImage: "trash", role: .destructive) {
                        pendingDelete = summaries[item.identity]
                    }
                    .disabled(exportingComic == item.identity)
                }
            },
        )
        .onGeometryChange(for: CGSize.self) { proxy in
            proxy.size
        } action: { size in
            gridContainerSize = size
        }
    }

    /// 导出该作品：菜单只在下载完成的作品上提供入口，未完成时构建计划会拒绝。
    private func beginExport(_ identity: ComicIdentity) {
        guard let exportModel else { return }

        exportModel.begin(comic: identity)
    }

    /// 分享面板关闭后提示保存结果：只有用户完成「存储到文件」才提示，取消与分享到其它 App 不打扰。
    private func showSaveResult(completed: Bool, activityIdentifier: String?) {
        guard completed,
              activityIdentifier?.lowercased().contains("savetofiles") == true
        else { return }

        ToastCenter.shared.show("已保存到「文件」", type: .success)
    }

    /// 点击卡片按下载状态分流：未完成时不进入详情——进行中／排队暂停、已暂停继续、失败重试；
    /// 只有已完成才打开离线详情。
    private func handleSelect(
        _ item: ComicListItem,
        summaries: [ComicIdentity: DownloadedComicSummary],
        model: DownloadsViewModel,
    ) {
        guard summaries[item.identity]?.state == .completed else {
            model.toggle(item.identity)
            return
        }

        openOfflineDetail(item)
    }

    private func openOfflineDetail(_ item: ComicListItem) {
        do {
            try shell.navigator.open(.detail(item.identity, mode: .offline))
        } catch {
            AppLogger.error("离线详情路由失败：\(type(of: error))", category: "App.Download")
            ToastCenter.shared.show("无法打开离线详情")
        }
    }

    /// 确认后删除该作品的下载（停止在途任务、删除文件与记录）；失败按原因提示，成功提示已删除。
    private func deleteDownload(_ summary: DownloadedComicSummary) {
        guard let model else { return }

        Task {
            do {
                try await model.delete(summary.identity)
                ToastCenter.shared.show("已删除《\(summary.title)》的下载", type: .success)
            } catch {
                AppLogger.error(
                    "下载记录删除失败，errorType=\(String(reflecting: type(of: error)))",
                    category: "App.Download",
                )
                ToastCenter.shared.show(deleteFailureMessage(error), type: .error)
            }
        }
    }

    private func deleteFailureMessage(_ error: any Error) -> String {
        if let assetError = error as? DownloadAssetError, let message = assetError.removalMessage {
            return message
        }
        if let removalError = error as? DownloadRemovalError {
            return removalError.message
        }
        return "删除失败，请稍后重试"
    }

    /// 封面叠层：来源 Logo（与观看历史一致，左上角）在下，下载蒙版＋进度圆环、导出进度蒙版在上；整体不拦截点击。
    private func coverOverlay(
        summary: DownloadedComicSummary?,
        identity: ComicIdentity,
        descriptors: [ComicSourceID: SourceDescriptor],
    ) -> some View {
        ZStack {
            if let logo = summary.flatMap({ descriptors[$0.identity.sourceID]?.logo }) {
                SourceLogoView(logo, size: 14)
                    .padding(6)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }

            if let summary {
                DownloadCoverOverlay(summary: summary)
            }

            if let exportModel {
                ExportProgressBadge(model: exportModel, identity: identity)
            }
        }
        .allowsHitTesting(false)
    }

    /// 下载作品卡片：作者作副标题，与历史卡片一致。
    private func makeCard(_ summary: DownloadedComicSummary) -> ComicListItem {
        ComicListItem(
            identity: summary.identity,
            title: summary.title,
            subtitle: summary.authors.isEmpty ? nil : summary.authors.joined(separator: "、"),
            cover: summary.cover,
        )
    }
}

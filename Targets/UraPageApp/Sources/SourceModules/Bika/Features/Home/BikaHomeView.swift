import SwiftUI

/// 哔咔首页：随机本子与最近更新（可续载），两个分区各自加载、谁先完成谁先显示。
///
/// 页面只做展示与路由：分区数据、加载状态与在途任务由 `BikaHomeModel` 持有，
/// 空态/失败态与骨架屏复用公共组件；右上角来源切换入口来自公共 `sourceRootChrome`。
struct BikaHomeView: View {
    @Environment(\.appShell) private var shell
    @Environment(\.bikaServices) private var services

    /// 页面级状态 owner；Services 来自本源 Environment，因此首次展示时创建。
    @State private var model: BikaHomeModel?

    var body: some View {
        SourceHomeScaffold(
            model: model,
            phase: { $0.loadState },
            isEmpty: { $0.isEmpty },
            failureTitle: "首页加载失败",
            emptyTitle: "暂无首页内容",
            emptyMessage: "稍后再来看看",
            onAppear: prepareModelAndLoadIfNeeded,
            onRetry: { $0.retry() },
            skeleton: {
                BikaHomeSkeletonView()
            },
            content: { model in
                BikaHomeContentView(
                    randomState: model.randomComics.loadState,
                    recentlyUpdatedState: model.recentlyUpdated.loadState,
                    recentlyUpdatedComics: model.recentlyUpdated.items,
                    isLoadingMore: model.recentlyUpdated.isLoadingMore,
                    canLoadMore: model.recentlyUpdated.canLoadMore,
                    loadMoreErrorMessage: model.recentlyUpdated.loadMoreError?.message,
                    onSelectComic: { item in
                        open(item)
                    },
                    onRetryFailedSection: {
                        model.retry()
                    },
                    onLoadMore: {
                        model.loadMoreIfNeeded()
                    },
                    onRetryLoadMore: {
                        model.retryLoadMore()
                    },
                )
            },
        )
    }

    /// 首次展示时创建状态 owner 并加载；切 Tab 回来不重复请求（已加载或已失败都保持）。
    private func prepareModelAndLoadIfNeeded() {
        if model == nil {
            model = BikaHomeModel(services: services)
        }

        model?.loadIfNeeded()
    }

    /// 点击卡片：push 本源漫画详情，跨来源转换由导航入口统一处理。
    private func open(_ item: ComicListItem) {
        shell.navigator.push(BikaRoute.detail(item.identity))
    }
}

import SwiftUI

/// 绅士首页（推荐）：按服务端分区展示推荐内容，分区内为固定三列网格。
///
/// 页面只做展示与路由：分区数据、加载状态与在途任务由公共 `SourceValueLoadModel` 持有，
/// 空态/失败态与骨架屏复用公共组件；右上角仍是来源切换入口。
struct ShenshiHomeView: View {
    @Environment(\.appShell) private var shell
    @Environment(\.shenshiServices) private var services
    @Environment(\.shenshiListFilterHandoff) private var listFilterHandoff

    /// 页面级状态 owner；Services 来自本源 Environment，因此首次展示时创建。
    @State private var model: SourceValueLoadModel<[ShenshiHomeSection]>?

    var body: some View {
        SourceHomeScaffold(
            model: model,
            phase: { $0.phase },
            isEmpty: { $0.items.isEmpty },
            failureTitle: "推荐页加载失败",
            emptyTitle: "暂无推荐内容",
            emptyMessage: "稍后再来看看",
            onAppear: prepareModelAndLoadIfNeeded,
            onRetry: { $0.retry() },
            skeleton: {
                ShenshiHomeSkeletonView()
            },
            content: { model in
                ShenshiHomeSectionsView(
                    sections: model.items,
                    onSelectComic: { item in
                        open(item)
                    },
                    onSelectUpdates: { categoryID in
                        openUpdates(categoryID: categoryID)
                    },
                )
            },
        )
    }

    /// 首次展示时创建状态 owner 并加载；切 Tab 回来不重复请求（已加载或已失败都保持）。
    private func prepareModelAndLoadIfNeeded() {
        if model == nil {
            let services = services
            model = SourceValueLoadModel(logCategory: "Shenshi.Home") {
                try await services.homeSections()
            }
        }

        model?.loadIfNeeded()
    }

    /// 点击卡片：push 本源漫画详情，跨来源转换由导航入口统一处理。
    private func open(_ item: ComicListItem) {
        shell.navigator.push(ShenshiRoute.detail(item.identity))
    }

    /// 点击分区标题：登记待消费分类后切到「更新」Tab 的根页面。
    ///
    /// 顺序不能反：目标页在选中时才会求值并读取登记值。先登记，页面首次展示就能一次成型地
    /// 按该分类加载；否则会先用默认查询请求一次列表，再被筛选请求重载一次。
    private func openUpdates(categoryID: Int?) {
        listFilterHandoff.requestUpdates(categoryID: categoryID)
        shell.selectRoot(of: SourceTab(ShenshiTab.updates))
    }
}

import SwiftUI

/// 禁漫首页：最上方是随机推荐分区，其后按服务端推广分区展示内容。
///
/// 页面只做展示与路由：分区数据、加载状态与在途任务由 `JMComicHomeModel` 持有，
/// 空态/失败态与骨架屏复用公共组件；右上角仍是来源切换入口。
/// 分区标题按本源 typed 语义跳转：分类 → 分类 Tab（带筛选），周刊/推广 → 二级页面。
struct JMComicHomeView: View {
    @Environment(\.appShell) private var shell
    @Environment(\.jmComicServices) private var services
    @Environment(\.jmComicListFilterHandoff) private var listFilterHandoff

    /// 页面级状态 owner；Services 来自本源 Environment，因此首次展示时创建。
    @State private var model: JMComicHomeModel?

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
                JMComicHomeSkeletonView()
            },
            content: { model in
                JMComicHomeSectionsView(
                    randomState: model.randomRecommendations.loadState,
                    sectionsState: model.sections.loadState,
                    onSelectComic: { item in
                        open(item)
                    },
                    onRetryRandom: {
                        model.randomRecommendations.retry()
                    },
                    onRetrySections: {
                        model.sections.retry()
                    },
                    onSelectCategory: { slug in
                        openCategories(slug: slug)
                    },
                    onSelectWeekly: { sectionTitle in
                        openWeekly(sectionTitle: sectionTitle)
                    },
                    onSelectPromotion: { sectionID, sectionTitle in
                        openPromotion(sectionID: sectionID, sectionTitle: sectionTitle)
                    },
                )
            },
        )
    }

    /// 首次展示时创建状态 owner 并加载；切 Tab 回来不重复请求（已加载或已失败都保持）。
    private func prepareModelAndLoadIfNeeded() {
        if model == nil {
            model = JMComicHomeModel(services: services)
        }

        model?.loadIfNeeded()
    }

    /// 点击卡片：push 本源漫画详情，跨来源转换由导航入口统一处理。
    private func open(_ item: ComicListItem) {
        shell.navigator.push(JMComicRoute.detail(item.identity))
    }

    /// 点击分类分区标题：登记待消费分类后切到「分类」Tab 的根页面。
    ///
    /// 顺序不能反：目标页在选中时才会求值并读取登记值。先登记，页面首次展示就能一次成型地
    /// 按该分类（并把排序重置为第一个选项）加载；否则会先用默认查询请求一次列表。
    private func openCategories(slug: String) {
        listFilterHandoff.requestCategory(slug: slug)
        shell.selectRoot(of: SourceTab(JMComicTab.categories))
    }

    /// 点击周刊分区标题：push 周刊页面，并沿用该分区的展示标题作为页面标题（与旧版一致）。
    private func openWeekly(sectionTitle: String) {
        shell.navigator.push(JMComicRoute.weekly(sectionTitle: sectionTitle))
    }

    /// 点击推广分区标题：push 该分区的推广列表，并沿用该分区的展示标题作为页面标题（与旧版一致）。
    private func openPromotion(sectionID: String, sectionTitle: String) {
        shell.navigator.push(
            JMComicRoute.promotion(sectionID: sectionID, sectionTitle: sectionTitle),
        )
    }
}

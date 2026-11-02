import Observation

/// 禁漫首页的页面级状态：顶部随机推荐与服务端推广分区来自两个接口，各自独立加载。
///
/// 生命周期与其它首页一致：任务由状态 owner 持有，切 Tab（页面不可见）不取消；
/// 状态被销毁（切源替换体验）时取消在途请求。
/// **两个分区互不等待**：谁先完成谁先显示，另一个仍在加载时由分区骨架占位。
/// 整页只在两个分区都失败时才进入失败态；单个分区失败时在各自位置就地提示与重试。
@MainActor
@Observable
final class JMComicHomeModel {
    /// 顶部随机推荐的漫画。
    let randomRecommendations: SourceValueLoadModel<[ComicListItem]>

    /// 服务端推广分区。
    let sections: SourceValueLoadModel<[JMComicHomeSection]>

    init(services: JMComicServices) {
        randomRecommendations = SourceValueLoadModel(logCategory: "JM.Home") {
            try await services.randomRecommendComics()
        }
        sections = SourceValueLoadModel(logCategory: "JM.Home") {
            try await services.homeSections()
        }
    }

    /// 页面首屏阶段：只用于整页骨架、整页失败与空态。
    ///
    /// 任一分区有结果就进入内容态，由内容视图按各分区自己的阶段显示内容或骨架；
    /// 两个分区都失败才整页失败（此时一个重试按钮同时重发两个请求）。
    var loadState: InitialLoadState<SourceLoadDisplayError> {
        if case let .failed(randomError) = randomRecommendations.loadState,
           case .failed = sections.loadState {
            return .failed(randomError)
        }

        if isAwaitingFirstResult {
            return .loading
        }

        return .loaded
    }

    /// 两个分区都还没有结果（未开始或加载中）。
    private var isAwaitingFirstResult: Bool {
        switch (randomRecommendations.loadState, sections.loadState) {
        case (.idle, .idle), (.idle, .loading), (.loading, .idle), (.loading, .loading):
            true

        default:
            false
        }
    }

    /// 两个分区都加载完成且都没有内容（整页空态）。
    var isEmpty: Bool {
        guard case let .loaded(random) = randomRecommendations.loadState,
              case let .loaded(sections) = sections.loadState
        else {
            return false
        }

        return random.isEmpty && sections.isEmpty
    }

    /// 首次展示时并行请求两个分区；都只请求一次（失败由页面重试）。
    func loadIfNeeded() {
        randomRecommendations.loadIfNeeded()
        sections.loadIfNeeded()
    }

    /// 整页失败态的重试：`SourceValueLoadModel.retry()` 只对失败分区重新发起请求。
    func retry() {
        randomRecommendations.retry()
        sections.retry()
    }
}

import SwiftUI

/// 来源首页的公共骨架：页面背景、首屏四态（骨架／空态／失败／内容）、根页外壳与首次加载入口。
///
/// 只负责状态分发与统一外观，不持有页面状态、不请求数据；具体模型由来源页面创建，
/// `phase`、`isEmpty`、失败标题、空态文案与内容槽由来源提供。
struct SourceHomeScaffold<Model, Content: View, Skeleton: View>: View {
    /// 页面状态 owner；`nil` 表示首帧尚未创建。
    let model: Model?

    /// 从模型取出首屏阶段。
    let phase: (Model) -> InitialLoadState<SourceLoadDisplayError>

    /// 首屏加载完成时内容是否为空。
    let isEmpty: (Model) -> Bool

    /// 首屏失败标题。
    let failureTitle: String

    /// 空态标题与说明。
    let emptyTitle: String
    let emptyMessage: String

    /// 首次出现时创建模型并触发加载。
    let onAppear: () -> Void

    /// 失败重试。
    let onRetry: (Model) -> Void

    @ContentBuilder let skeleton: () -> Skeleton
    @ContentBuilder let content: (Model) -> Content

    init(
        model: Model?,
        phase: @escaping (Model) -> InitialLoadState<SourceLoadDisplayError>,
        isEmpty: @escaping (Model) -> Bool,
        failureTitle: String,
        emptyTitle: String,
        emptyMessage: String,
        onAppear: @escaping () -> Void,
        onRetry: @escaping (Model) -> Void,
        @ContentBuilder skeleton: @escaping () -> Skeleton,
        @ContentBuilder content: @escaping (Model) -> Content,
    ) {
        self.model = model
        self.phase = phase
        self.isEmpty = isEmpty
        self.failureTitle = failureTitle
        self.emptyTitle = emptyTitle
        self.emptyMessage = emptyMessage
        self.onAppear = onAppear
        self.onRetry = onRetry
        self.skeleton = skeleton
        self.content = content
    }

    var body: some View {
        ZStack {
            Color.pageBackground.ignoresSafeArea()

            InitialLoadView(
                model: model,
                initialState: phase,
                isEmpty: isEmpty,
            ) {
                skeleton()
            } empty: {
                EmptyStateView(title: emptyTitle, message: emptyMessage)
            } failure: { model, error in
                LoadErrorView(title: failureTitle, message: error.message) {
                    onRetry(model)
                }
            } content: { model in
                content(model)
            }
        }
        .sourceRootChrome()
        .onAppear(perform: onAppear)
    }
}

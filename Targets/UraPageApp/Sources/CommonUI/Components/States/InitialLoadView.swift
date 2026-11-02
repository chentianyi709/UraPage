import SwiftUI

/// 首屏加载的公共编排：按状态在骨架、空态、失败与内容四个槽之间分发。
///
/// 只决定“哪种状态显示哪一槽”，不持有状态、不请求数据、不决定文案：
/// 状态与请求由页面自己的生命周期 owner 持有（如 `ComicPagingModel`、来源首页模型），
/// 首屏阶段与空判定通过闭包从 model 取出，四个槽、空态方案与失败标题由页面提供
/// （失败说明文案来自页面给出的展示错误）。
///
/// model 是可选：状态 owner 由页面在首次展示时创建（Services 只能从 Environment 读），
/// 因此 `nil`（首帧，尚未创建）与加载中一样显示骨架；其余三个槽都拿到已解包的 model，
/// 页面不再自己写一次 `if let model … else 骨架`。
struct InitialLoadView<
    Model,
    Failure: Equatable & Sendable,
    Loading: View,
    Empty: View,
    FailureContent: View,
    Content: View,
>: View {
    /// 页面状态 owner；`nil` 表示尚未创建（首帧）。
    let model: Model?

    /// 从 model 取出首屏阶段（未开始与加载中都显示骨架）。
    let initialState: (Model) -> InitialLoadState<Failure>

    /// 首屏加载完成时，内容是否为空。
    let isEmpty: (Model) -> Bool

    @ContentBuilder let loading: () -> Loading
    @ContentBuilder let empty: () -> Empty
    @ContentBuilder let failure: (Model, Failure) -> FailureContent
    @ContentBuilder let content: (Model) -> Content

    var body: some View {
        if let model {
            switch initialState(model) {
            case .idle, .loading:
                loading()

            case let .failed(error):
                failure(model, error)

            case .loaded:
                if isEmpty(model) {
                    empty()
                } else {
                    content(model)
                }
            }
        } else {
            loading()
        }
    }
}

import SwiftUI

/// 按单值加载状态展示骨架、失败或内容；页面状态 owner 尚未创建时展示骨架。
struct InitialValueLoadView<
    Model,
    Value: Sendable,
    Loading: View,
    FailureContent: View,
    Content: View,
>: View {
    let model: Model?
    let initialState: (Model) -> InitialValueLoadState<Value>

    @ContentBuilder let loading: () -> Loading
    @ContentBuilder let failure: (Model, SourceLoadDisplayError) -> FailureContent
    @ContentBuilder let content: (Value) -> Content

    var body: some View {
        if let model {
            switch initialState(model) {
            case .idle, .loading:
                loading()

            case let .failed(error):
                failure(model, error)

            case let .loaded(value):
                content(value)
            }
        } else {
            loading()
        }
    }
}

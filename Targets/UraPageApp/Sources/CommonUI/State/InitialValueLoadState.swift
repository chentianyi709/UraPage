/// 单值页面的首次加载状态；成功时直接携带服务返回的值，不存在列表空态。
enum InitialValueLoadState<Value: Sendable>: Sendable {
    case idle
    case loading
    case loaded(Value)
    case failed(SourceLoadDisplayError)
}

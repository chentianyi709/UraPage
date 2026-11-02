/// 描述页面从尚未请求到首次内容加载完成的通用阶段。
enum InitialLoadState<Failure: Equatable & Sendable>: Equatable, Sendable {
    /// 页面尚未开始首次请求。
    case idle

    /// 页面正在执行首次请求。
    case loading

    /// 首次请求已成功完成；空内容由具体页面自行判断。
    case loaded

    /// 首次请求失败，并保存页面自己的展示错误。
    case failed(Failure)
}

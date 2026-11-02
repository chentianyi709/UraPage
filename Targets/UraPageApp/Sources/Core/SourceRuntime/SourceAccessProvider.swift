/// 来源账号的唯一事实来源：持有当前登录状态、共享恢复任务并发布变化。
///
/// 需要登录的来源在自己的账号访问 owner 上实现本协议（例如 `BikaAccountAccessStore`）；
/// 页面不自行判断登录，由 App 门禁统一读取（`SourceAccessRequirement`）。
@MainActor
protocol SourceAccessProvider: AnyObject {
    /// 当前访问事实；门禁据此渲染检查态／未登录态／失败态／真实页面。
    var current: SourceAccessSnapshot { get }

    /// 恢复本源账号；并发调用共享同一次恢复，已完成后不重复执行。
    func ensureRestored() async

    /// 恢复失败后的显式重试。
    func retryRestoration() async

    /// 订阅访问事实变化；订阅时先给出当前快照，使用 `bufferingNewest(1)`。
    func updates() -> AsyncStream<SourceAccessSnapshot>
}

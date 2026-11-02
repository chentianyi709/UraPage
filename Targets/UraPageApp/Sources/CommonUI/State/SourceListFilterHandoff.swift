import Observation

/// 来源内「把一次列表筛选交接给目标列表页」的待消费登记（任意页面都可发起）。
///
/// 发起方（当前是首页分区标题；后续二级页同样可以）声明了 typed 跳转语义，但目标列表页是
/// 公共 `SourceListPage`，它的状态在页面自己的 owner 里，外部无法直接改查询；因此交接表达为
/// 「先登记一次待消费筛选，再切到该 Tab 的根页面」：目标页把登记值换算成
/// `SourceListFilterRequest`（可含多条菜单选择）并应用。
///
/// 一个登记器对应**一个**目标列表页，筛选值类型由来源给出（值里带不带目标区分由来源决定）；
/// 若要交接给两个不同目标页，用两个登记器或把值类型做成枚举。
///
/// `token` 单调递增且不清空：每次登记都是一次新请求，目标页按序号只应用一次；
/// 重复登记同一个筛选时目标页判定“与当前查询相同”而不重载。切源后体验重建，登记自然归零。
@MainActor
@Observable
final class SourceListFilterHandoff<Value: Equatable & Sendable> {
    /// 一次交接请求：筛选值 + 请求序号（序号从 1 开始）。
    struct Pending: Equatable, Sendable {
        let value: Value
        let token: Int
    }

    private(set) var pending: Pending?

    /// 登记一次交接；无效值是否忽略由来源的 `request...` 封装决定。
    func request(_ value: Value) {
        let token = (pending?.token ?? 0) + 1
        pending = Pending(value: value, token: token)
    }
}

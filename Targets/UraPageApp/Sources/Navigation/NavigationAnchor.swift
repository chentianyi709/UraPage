import Foundation

/// 发起一次（可能异步的）导航时记录的可见位置。
///
/// 用于 §8.2 的迟到导航校验：导航真正落地时，只有锚点仍然有效、
/// 且目标栈顶没有变化，才允许 push；否则丢弃该次导航。
nonisolated struct NavigationAnchor: Hashable, Sendable {
    /// 所属栈的稳定身份；nil 表示发起时没有激活的栈。
    let routerID: UUID?

    /// 发起时该 Tab 的可见栈顶；`nil` 表示当时在根页面。
    let top: AnySourceRoute?

    /// 发起时该 Tab 导航作用域的代次；切源/重置后旧锚点失效。
    let generation: Int
}

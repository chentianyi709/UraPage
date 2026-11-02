import Foundation
import Observation
import SwiftUI

/// 导航日志分类：只记录路由身份与栈深，不记录页面数据。
private let navigationLogCategory = "Navigation"

/// 一个 Tab 的导航栈；`path` 只有它一个 owner（§8.2）。
///
/// 只保存 route identity（`AnySourceRoute`），不保存 ViewModel、DTO、Services 或已加载数据。
/// 切源时实例保留（轻量导航不销毁），页面数据由体验状态负责释放。
@MainActor
@Observable
final class AppRouter {
    /// 稳定栈身份，避免不同 Tab 的相同栈顶与代次被误认为同一位置。
    private let id = UUID()

    private(set) var path: [AnySourceRoute] = []

    /// 导航作用域代次：切源或重置时递增，使已发出的异步导航锚点失效（§9.2 第 3 步）。
    private(set) var generation = 0

    /// 当前可见栈顶；`nil` 表示停留在根页面。
    var visibleTop: AnySourceRoute? {
        path.last
    }

    /// 返回当前锚点，供异步导航在落地前校验。
    var anchor: NavigationAnchor {
        NavigationAnchor(routerID: id, top: visibleTop, generation: generation)
    }

    /// 暴露给 `NavigationStack(path:)` 的绑定。
    var pathBinding: Binding<[AnySourceRoute]> {
        Binding(
            get: { self.path },
            set: { self.path = $0 },
        )
    }

    /// 追加一个 push 目标。
    func push(_ route: AnySourceRoute) {
        path.append(route)
        AppLogger.debug("push 路由 \(route)，栈深=\(path.count)", category: navigationLogCategory)
    }

    /// 只在锚点仍有效且栈顶未变时 push；迟到导航被丢弃并返回 `false`。
    @discardableResult
    func push(_ route: AnySourceRoute, ifAnchorStillValid anchor: NavigationAnchor) -> Bool {
        guard anchor.routerID == id, anchor.generation == generation, anchor.top == visibleTop else {
            // 切源或栈顶已变：丢弃这次导航，不把页面推到用户当前所在的位置。
            AppLogger.debug(
                "丢弃迟到导航 \(route)，锚点代次=\(anchor.generation)，当前代次=\(generation)",
                category: navigationLogCategory,
            )
            return false
        }

        path.append(route)
        AppLogger.debug("push 路由 \(route)，栈深=\(path.count)", category: navigationLogCategory)
        return true
    }

    /// 返回上一级；已在根页面时不做任何事。
    func pop() {
        guard !path.isEmpty else {
            return
        }

        path.removeLast()
    }

    /// 返回根页面。
    func popToRoot() {
        guard !path.isEmpty else {
            return
        }

        path.removeAll()
        AppLogger.debug("返回根页面", category: navigationLogCategory)
    }

    /// 使已发出的导航锚点失效（切源事务第 3 步）；不清空 path。
    ///
    /// 逐 Tab 调用，不在这里记录日志：调用方（`SourceNavigationState`）汇总成一条。
    func invalidateAnchors() {
        generation += 1
    }
}

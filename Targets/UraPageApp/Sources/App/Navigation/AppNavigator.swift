/// 页面可用的导航入口；由 `AppShellView` 在体验根边界安装。
///
/// 导航动作集中在这里：定位当前 Tab 的 `AppRouter`、包装来源 typed route、
/// 把跨来源链接交给目标来源解析。页面只发起导航，不知道自己的 Tab 与栈结构（§8.1）。
/// 未安装时调用即暴露装配错误，不做静默降级。
@MainActor
struct AppNavigator {
    private let model: AppShellModel
    private let host: AppSourceHost

    init(model: AppShellModel, host: AppSourceHost) {
        self.model = model
        self.host = host
    }

    /// 当前 Tab 的导航锚点；异步导航前保存它，落地时用 `push(_:ifAnchorStillValid:)` 校验。
    ///
    /// TODO: 锚点 API 目前没有调用方（`anchor` 与 `push(_:ifAnchorStillValid:)` 均未被页面使用）。
    /// 保留用于异步导航落地后丢弃迟到结果；接入首个消费者（网络回跳、Reader 异步跳转等）时，
    /// 验证切源或栈顶变化后旧结果确实被丢弃，然后删除本 TODO。
    var anchor: NavigationAnchor {
        guard let router = model.activeRouter else {
            // 没有激活体验时返回永不匹配的代次，使切源瞬间的异步导航被丢弃。
            return NavigationAnchor(routerID: nil, top: nil, generation: -1)
        }

        return router.anchor
    }

    /// push 一个来源 typed route（本源或跨来源）；跨来源路由同样落在发起方栈。
    func push(_ route: some SourceRouteValue) {
        push(AnySourceRoute(route))
    }

    /// push 已擦除的路由；只供 `open(_:)` 与 typed 重载内部使用，页面统一传 typed route。
    private func push(_ route: AnySourceRoute) {
        model.activeRouter?.push(route)
    }

    /// 打开跨来源链接：由目标来源把公共语义解析成本源路由后再 push。
    func open(_ link: SourceLink) throws {
        try push(host.resolve(link))
    }

    /// 只在锚点仍有效且栈顶未变时 push；迟到导航被丢弃。
    @discardableResult
    func push(_ route: some SourceRouteValue, ifAnchorStillValid anchor: NavigationAnchor) -> Bool {
        push(AnySourceRoute(route), ifAnchorStillValid: anchor)
    }

    /// 只在锚点仍有效且栈顶未变时 push 已擦除的路由；迟到导航被丢弃。
    @discardableResult
    func push(_ route: AnySourceRoute, ifAnchorStillValid anchor: NavigationAnchor) -> Bool {
        model.activeRouter?.push(route, ifAnchorStillValid: anchor) ?? false
    }

    /// 返回上一级。
    func pop() {
        model.activeRouter?.pop()
    }

    /// 返回根页面。
    func popToRoot() {
        model.activeRouter?.popToRoot()
    }
}

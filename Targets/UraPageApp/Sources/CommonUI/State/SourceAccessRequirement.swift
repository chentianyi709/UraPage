import SwiftUI

/// 门禁内呈现的本源登录入口。
///
/// 由来源提供登录页面；呈现由 `SourceAccessGate` 单点持有，页面自己用 `\.dismiss` 关闭。
/// 这样本源内页面与跨来源 push 进来的页面都能弹出本源登录：跨来源时本源体验根不在视图层级内，
/// 没有可用的呈现位置，因此登录内容随访问声明一起交给门禁（2026-09-20 决策，无需 `RouteContext`）。
@MainActor
struct SourceLoginContent {
    private let makeBody: () -> AnyView

    init(@ContentBuilder body: @escaping () -> some View) {
        makeBody = { AnyView(body()) }
    }

    /// 取出要呈现的登录页面。
    func body() -> AnyView {
        makeBody()
    }
}

/// 页面的访问要求：公开内容或需要登录。
///
/// 由来源声明：二级页走 `SourceExperienceModule.defaultAccessRequirement` 声明一次，
/// Tab 侧在 `SourceTabContainer.accessRequirement` 闭包里引用同一份本源规则；
/// App 统一门禁读取（`SourceAccessGate`），门禁不判断来源与业务，只按声明渲染。
/// 离线路由只读本机资产，由公共边界自动按 `.publicContent` 处理，来源不需要声明。
@MainActor
enum SourceAccessRequirement {
    /// 公开页面：不需要登录，直接展示。
    case publicContent

    /// 需要登录的页面：`provider` 提供访问事实，`login` 打开本源登录入口。
    ///
    /// 登录成功后由 `provider` 发布 `.authenticated`：页面在原位切换、不需要重新导航或重复 push，
    /// 仍在展示的登录弹窗也由门禁关闭。
    case authenticated(
        any SourceAccessProvider,
        login: SourceLoginContent,
    )
}

extension EnvironmentValues {
    /// 当前来源的账号访问事实；由来源体验根安装（`SourceExperienceModule.root`），
    /// 供根页面头像按登录态着色。匿名来源为 `nil`。
    @Entry var sourceAccountAccess: (any SourceAccessProvider)?
}

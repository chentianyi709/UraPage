import SwiftUI

/// 哔咔体验根视图：固定 TabBar 容器。
///
/// 各 Tab 的导航栈由 `AppNavigationStack` 统一承载，来源只提供根页面与访问规则：
/// 本源除书架外的 Tab 都需要登录，门禁由公共 `SourceAccessGate` 在页面之外判断，
/// 未登录时不会发出任何业务请求。二级页由 `BikaModule.defaultAccessRequirement` 使用同一份规则，
/// 公共 destination 边界统一套门禁。
struct BikaRootView: View {
    let experience: BikaExperience

    /// 本源 Services；列表页描述工厂与账号 owner 都需要它。未安装即暴露装配错误。
    @Environment(\.bikaServices) var services: BikaServices

    var body: some View {
        SourceTabContainer(
            navigation: experience.navigation,
            accessRequirement: { tab in
                BikaAccess.requirement(
                    for: tab,
                    access: services.account.access,
                )
            },
            tabRoot: { tab in BikaTabRootContent(experience: experience, tab: tab) },
        )
    }
}

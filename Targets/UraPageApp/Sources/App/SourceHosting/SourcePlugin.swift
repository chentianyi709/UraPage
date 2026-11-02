import SwiftUI

/// 一个来源在 App 内的完整注册单元（§19.5）。
///
/// 字段全部必填：漏接来源在装配/启动校验处暴露，不做兜底。宿主只按 `sourceID` 查表，
/// 不做来源 `switch`；各来源的具体 `Experience`/`Root` 类型只在初始化时出现一次，
/// typed `Route` 的解包与页面构建都由来源 Module 自己完成。
@MainActor
struct SourcePlugin {
    /// 来源展示信息与固定 Tab 定义。
    let descriptor: SourceDescriptor

    /// 该来源首次激活时展示的 Tab；`SourceTab` 的来源分派点由来源自己声明。
    let defaultTab: SourceTab

    /// Module 所用 Services 的公共能力视图；不重建 Client，也不包含 UI 状态。
    let runtime: any ComicSourceRuntime

    /// 用本次激活的导航与资源构建该来源体验。
    private let buildExperience: (SourceNavigationState, ExperienceResources) -> ActiveSourceExperience

    /// 构建本源 route 的页面；typed route 的解包失败属于装配错误。
    private let buildDestination: (AnySourceRoute) -> AnyView

    /// 构建本源设置弹窗内容。
    private let buildSettingsSheet: () -> AnyView

    /// 把公共跳转目标解析成本来源路由，再包装为擦除容器。
    private let buildResolvedRoute: (SourceLink) throws -> AnySourceRoute

    /// 用某个来源的体验 Module 建立注册单元；这是唯一接触具体 Module 类型的地方。
    init(_ module: some SourceExperienceModule) {
        let defaultTab = SourceTab(module.defaultTab)
        // 默认 Tab 必须属于本源：写错来源属于装配错误，直接暴露。
        precondition(
            defaultTab.sourceID == module.descriptor.sourceID,
            "默认 Tab 与来源不匹配：\(defaultTab.sourceID.rawValue) vs \(module.descriptor.sourceID.rawValue)",
        )

        descriptor = module.descriptor
        runtime = module.services
        self.defaultTab = defaultTab
        buildExperience = { navigation, resources in
            let experience = module.makeExperience(navigation: navigation, resources: resources)
            return ActiveSourceExperience(
                sourceID: module.descriptor.sourceID,
                state: experience,
                navigation: navigation,
                // 调用协议的公共边界，统一安装 Services、展示信息与图片工作域。
                root: AnyView(module.root(experience: experience)),
            )
        }
        buildDestination = { route in
            module.destination(for: route)
        }
        buildSettingsSheet = {
            AnyView(module.settingsSheet())
        }
        buildResolvedRoute = { link in
            let route = try module.resolve(link)
            // 来源写错自己的 case 属于装配错误，直接暴露而不是把页面渲染到别的来源。
            precondition(
                route.sourceID == module.descriptor.sourceID,
                "跳转路由来源与 Module 不匹配：\(route.sourceID.rawValue)",
            )
            // 擦除只在 Plugin 发生：来源只产出本源 typed route。
            return AnySourceRoute(route)
        }
    }

    /// 构建一次激活的体验（内部完成资源创建与根视图类型擦除）。
    func makeExperience(
        navigation: SourceNavigationState,
        resources: ExperienceResources,
    ) -> ActiveSourceExperience {
        buildExperience(navigation, resources)
    }

    /// 构建本源 route 的页面。
    func destination(for route: AnySourceRoute) -> AnyView {
        buildDestination(route)
    }

    /// 把公共跳转目标解析成本来源路由。
    func resolve(_ link: SourceLink) throws -> AnySourceRoute {
        try buildResolvedRoute(link)
    }

    /// 构建本源设置弹窗内容。
    func makeSettingsSheet() -> AnyView {
        buildSettingsSheet()
    }
}

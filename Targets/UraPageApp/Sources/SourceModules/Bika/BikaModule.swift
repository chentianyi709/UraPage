import SwiftUI

/// 哔咔在 App 内的体验装配点；与 Catalog 使用同一个稳定 `BikaServices`。
@MainActor
struct BikaModule: SourceExperienceModule {
    let services = BikaServices()

    var defaultTab: BikaTab {
        .home
    }

    var servicesKey: WritableKeyPath<EnvironmentValues, BikaServices?> {
        \.bikaServicesStorage
    }

    /// 来源展示信息；Logo 资源名指向 App Assets。
    var descriptor: SourceDescriptor {
        SourceDescriptor(sourceID: services.sourceID, displayName: "哔咔漫画", logo: .asset("BikaSourceLogo"))
    }

    /// 哔咔账号访问事实；供根页面头像按登录态着色。
    var accountAccess: (any SourceAccessProvider)? {
        services.account.access
    }

    func makeExperience(
        navigation: SourceNavigationState,
        resources: ExperienceResources,
    ) -> BikaExperience {
        BikaExperience(
            navigation: navigation,
            resources: resources,
            browsingImages: services.makeBrowsingImages(),
        )
    }

    /// 体验根视图：只安装本源独有的体验状态，通用依赖由协议边界统一安装。
    func makeRoot(experience: BikaExperience) -> some View {
        BikaRootView(experience: experience)
    }

    /// 来源设置弹窗（App 级路由呈现）：分页仍用公共默认（个人中心／漫画源设置＋固定最后的通用设置），
    /// TabBar 上「个人中心」在第一位，打开时默认停在「漫画源设置」；
    /// 「漫画源设置」提供服务器线路，「个人中心」提供真实账号页（未登录＝公共登录表单，已登录＝资料与退出）。
    ///
    /// 本源 Services、展示信息和图片会话由公共组合边界安装；
    /// 图片工作域由 `AppSourceHost` 统一安装。
    func makeSettingsSheet() -> some View {
        standardSourceSettingsSheet {
            BikaSourceSettingsPage()
        } account: {
            BikaAccountPage()
        }
    }

    /// push 目标内容；公共组合边界按本源 key 安装依赖并统一套访问门禁，跨来源 push 同样生效。
    func makeDestination(for route: BikaRoute) -> some View {
        BikaDestinationView(route: route)
    }

    /// 把收藏的书签还原成本源列表页：payload 是本源收藏时编码的 typed 值。
    func resolve(_ bookmark: Bookmark) throws -> BikaRoute {
        switch bookmark.kind {
        case .category:
            try .categoryComics(bookmark.decoded(BikaComicCategory.self))
        case .tag:
            try .tagComics(bookmark.decoded(String.self))
        case .author:
            try .contributorComics(bookmark.decoded(BikaComicContributor.self))
        }
    }

    /// 本源在线内容的统一访问要求：整个来源只声明这一次；二级页由公共边界套用，
    /// Tab 侧在 `BikaRootView` 的 `accessRequirement` 闭包里引用同一份本源规则（`BikaAccess`）。
    ///
    /// 离线详情与离线 Reader 由公共边界按 `BikaRoute.usesLocalAssetsOnly` 放行，
    /// 这里不需要再列离线路由，新增二级页也不需要回来补门禁。
    var defaultAccessRequirement: SourceAccessRequirement {
        BikaAccess.protectedRequirement(access: services.account.access)
    }
}

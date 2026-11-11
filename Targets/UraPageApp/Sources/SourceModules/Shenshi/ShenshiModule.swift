import SwiftUI

/// 绅士在 App 内的体验装配点；与 Catalog 使用同一个稳定 `ShenshiServices`。
@MainActor
struct ShenshiModule: SourceExperienceModule {
    let services = ShenshiServices()

    var defaultTab: ShenshiTab {
        .recommended
    }

    var servicesKey: WritableKeyPath<EnvironmentValues, ShenshiServices?> {
        \.shenshiServicesStorage
    }

    /// 来源展示信息；绅士暂无 Logo 资源。
    var descriptor: SourceDescriptor {
        SourceDescriptor(
            sourceID: services.sourceID,
            displayName: "绅士漫画",
            logo: .drawn(monogram: "绅"),
            tagKinds: [.author, .category, .tag],
        )
    }

    /// 绅士账号访问事实；供根页面头像按登录态着色。
    var accountAccess: (any SourceAccessProvider)? {
        services.account.access
    }

    func makeExperience(
        navigation: SourceNavigationState,
        resources: ExperienceResources,
    ) -> ShenshiExperience {
        ShenshiExperience(
            navigation: navigation,
            resources: resources,
            browsingImages: services.makeBrowsingImages(),
        )
    }

    /// 体验根视图：只安装本源独有的体验状态，通用依赖由协议边界统一安装。
    func makeRoot(experience: ShenshiExperience) -> some View {
        ShenshiRootView(experience: experience)

            .environment(\.shenshiListFilterHandoffStorage, experience.listFilterHandoff)
    }

    /// 来源设置弹窗（App 级路由呈现）：分页仍用公共默认（个人中心／漫画源设置＋固定最后的通用设置），
    /// TabBar 上「个人中心」在第一位，打开时默认停在「漫画源设置」；
    /// 「漫画源设置」提供服务器线路，「个人中心」提供真实账号页（未登录＝公共登录表单，已登录＝资料与退出）。
    ///
    /// 本源 Services、展示信息和图片会话由公共组合边界安装；
    /// 图片工作域由 `AppSourceHost` 统一安装。
    func makeSettingsSheet() -> some View {
        standardSourceSettingsSheet {
            ShenshiSourceSettingsPage()
        } account: {
            ShenshiAccountPage()
        }
    }

    /// push 目标内容；公共组合边界按本源 key 安装依赖并统一套访问门禁，跨来源 push 同样生效。
    ///
    /// 绅士允许匿名浏览，不声明 `defaultAccessRequirement`（默认公开），二级页不写门禁代码。
    func makeDestination(for route: ShenshiRoute) -> some View {
        ShenshiDestinationView(route: route)
    }

    /// 把收藏的书签还原成本源列表页：payload 是本源收藏时编码的 typed 值。
    func resolve(_ bookmark: Bookmark) throws -> ShenshiRoute {
        switch bookmark.kindID {
        case ComicTagKind.category.id:
            try .categoryComics(bookmark.decoded(ShenshiLatestCategory.self))
        case ComicTagKind.tag.id:
            try .tagComics(bookmark.decoded(ShenshiComicTag.self))
        case ComicTagKind.author.id:
            try .publisherComics(bookmark.decoded(ShenshiComicPublisher.self))
        default:
            // 本源没有这个维度的列表页（例如来源升级后移除的维度）。
            throw ComicSourceError.invalidIdentity
        }
    }
}

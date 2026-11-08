import SwiftUI

/// 禁漫在 App 内的体验装配点；与 Catalog 使用同一个稳定 `JMComicServices`。
@MainActor
struct JMComicModule: SourceExperienceModule {
    let services = JMComicServices()

    var defaultTab: JMComicTab {
        .home
    }

    var servicesKey: WritableKeyPath<EnvironmentValues, JMComicServices?> {
        \.jmComicServicesStorage
    }

    /// 来源展示信息；Logo 资源名指向 App Assets。
    var descriptor: SourceDescriptor {
        SourceDescriptor(
            sourceID: services.sourceID,
            displayName: "禁漫天堂",
            logo: .asset("JMComicSourceLogo"),
            tagKinds: [.author, .tag],
        )
    }

    /// 禁漫账号访问事实；供根页面头像按登录态着色。
    var accountAccess: (any SourceAccessProvider)? {
        services.account.access
    }

    func makeExperience(
        navigation: SourceNavigationState,
        resources: ExperienceResources,
    ) -> JMComicExperience {
        JMComicExperience(
            navigation: navigation,
            resources: resources,
            browsingImages: services.makeBrowsingImages(),
        )
    }

    /// 体验根视图：只安装本源独有的体验状态，通用依赖由协议边界统一安装。
    func makeRoot(experience: JMComicExperience) -> some View {
        JMComicRootView(experience: experience)

            .environment(\.jmComicListFilterHandoffStorage, experience.listFilterHandoff)
    }

    /// 来源设置弹窗（App 级路由呈现）：分页仍用公共默认（个人中心／漫画源设置＋固定最后的通用设置），
    /// TabBar 上「个人中心」在第一位，打开时默认停在「漫画源设置」；
    /// 「漫画源设置」提供服务器线路， 「个人中心」提供真实账号页（未登录＝公共登录表单，已登录＝资料与退出）。
    ///
    /// 本源 Services、展示信息和图片会话由公共组合边界安装；
    /// 图片工作域由 `AppSourceHost` 统一安装。
    func makeSettingsSheet() -> some View {
        standardSourceSettingsSheet {
            JMComicSourceSettingsPage()
        } account: {
            JMComicAccountPage()
        }
    }

    /// push 目标内容；公共组合边界按本源 key 安装依赖并统一套访问门禁，跨来源 push 同样生效。
    ///
    /// 禁漫允许匿名浏览，不声明 `defaultAccessRequirement`（默认公开），二级页不写门禁代码。
    func makeDestination(for route: JMComicRoute) -> some View {
        JMComicDestinationView(route: route)
    }

    /// 把收藏的书签还原成本源列表页：作者与标签都是固定关键词，查询词即 payload。
    func resolve(_ bookmark: Bookmark) throws -> JMComicRoute {
        switch bookmark.kindID {
        case ComicTagKind.author.id:
            try .queryComics(query: bookmark.decoded(String.self))
        case ComicTagKind.tag.id:
            try .tagComics(bookmark.decoded(String.self))
        default:
            // 禁漫没有分类页，本源不会产出这类收藏。
            throw ComicSourceError.invalidIdentity
        }
    }
}

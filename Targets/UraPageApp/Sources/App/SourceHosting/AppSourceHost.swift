import SwiftUI

/// 按来源插件表创建体验与根视图。
///
/// 宿主只做“查表 + 建资源”，不含任何来源 `switch`；来源分派只存在于
/// `AppSourceRegistrations` 的 Module 清单；默认 Tab 由各来源 Module 声明（§7.1）。
@MainActor
struct AppSourceHost: SourceDestinationResolving {
    private let plugins: [ComicSourceID: SourcePlugin]

    /// 注册顺序：来源列表的初始顺序，也是默认来源（第一个）；用户排序由 App Shell 管理。
    let orderedSourceIDs: [ComicSourceID]

    private let imageStore: BrowsingImageStore

    /// App 级来源设置弹窗里展示图片用的工作域（账号头像等）：随宿主创建一次，不与体验共享内存缓存。
    ///
    /// 弹窗不在体验根层级内，拿不到 `ExperienceResources` 的图片工作域，因此由宿主提供一份；
    /// 各来源的图片解析能力由 Module 的公共 settingsSheet 组合边界安装。
    private let settingsImageScope: BrowsingImageScope

    /// 用插件表建立宿主；重复注册同一来源属于装配错误，直接暴露。
    init(plugins: [SourcePlugin], imageStore: BrowsingImageStore) {
        self.plugins = Dictionary(uniqueKeysWithValues: plugins.map {
            ($0.descriptor.sourceID, $0)
        })
        orderedSourceIDs = plugins.map(\.descriptor.sourceID)
        self.imageStore = imageStore
        settingsImageScope = imageStore.makeScope()
    }

    /// 首次安装时的默认来源：注册顺序第一个（禁漫）。
    ///
    /// 空表是装配错误（启动校验会先失败），这里直接暴露。
    var defaultSourceID: ComicSourceID {
        guard let first = orderedSourceIDs.first else {
            preconditionFailure("来源注册为空：无法确定默认来源")
        }

        return first
    }

    /// 该来源首次激活时的轻量导航状态；默认 Tab 来自来源 Module。
    func defaultNavigationState(for sourceID: ComicSourceID) -> SourceNavigationState {
        SourceNavigationState(selectedTab: plugin(for: sourceID).defaultTab)
    }

    /// 来源选择入口使用的展示清单；顺序即注册顺序，缺失注册与其它查表一致地暴露。
    var descriptors: [SourceDescriptor] {
        orderedSourceIDs.map { plugin(for: $0).descriptor }
    }

    /// 创建一次来源激活的体验；缺失注册代表装配错误，直接暴露，不做兜底（§8.2）。
    func makeExperience(
        sourceID: ComicSourceID,
        navigation: SourceNavigationState,
    ) -> ActiveSourceExperience {
        plugin(for: sourceID).makeExperience(
            navigation: navigation,
            resources: ExperienceResources(imageStore: imageStore),
        )
    }

    /// 构建一个 push 目标的页面。
    ///
    /// 按 `route.sourceID` 查注册表，因此跨来源 push 也能拿到目标来源自己的页面；
    /// 目标来源的依赖由该来源的 destination 自己安装，不与发起方环境混用（§8.2）。
    func destination(for route: AnySourceRoute) -> AnyView {
        plugin(for: route.sourceID).destination(for: route)
    }

    /// 构建某个来源的设置弹窗内容（App 级路由呈现，内容归来源 Module）。
    ///
    /// 图片工作域由宿主安装，目标 Module 的公共边界安装本源图片解析能力与 Services。
    func settingsSheet(for sourceID: ComicSourceID) -> AnyView {
        AnyView(
            plugin(for: sourceID)
                .makeSettingsSheet()
                .environment(\.browsingImageScopeStorage, settingsImageScope),
        )
    }

    /// 把公共跳转目标解析成目标来源的路由（跨来源跳转）。
    ///
    /// `link` 自带 `sourceID`，宿主只查表，不解释具体语义。
    func resolve(_ link: SourceLink) throws -> AnySourceRoute {
        try plugin(for: link.sourceID).resolve(link)
    }

    /// 插件查找共用一个装配错误边界，不为缺失来源创建默认实现。
    private func plugin(for sourceID: ComicSourceID) -> SourcePlugin {
        guard let plugin = plugins[sourceID] else {
            preconditionFailure("来源未注册：\(sourceID.rawValue)")
        }

        return plugin
    }
}

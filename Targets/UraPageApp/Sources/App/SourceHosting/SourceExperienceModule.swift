import SwiftUI

/// 来源体验状态：只负责页面状态失效与释放（§6.1）。
@MainActor
protocol SourceExperienceState: AnyObject {
    /// 本次激活独占的资源（图片工作域）；在体验组合边界创建，随体验销毁。
    var resources: ExperienceResources { get }

    /// 本次激活的图片解析会话，根边界安装一次。
    var browsingImages: any ComicImageService { get }

    /// 切源销毁本体验前调用：取消页面任务、释放列表与页面状态。
    ///
    /// 只处理非视图持有的页面状态（在途任务、外部会话、缓存）；页面数据本身是 `@State`，
    /// 随根视图从视图层级移除由 SwiftUI 释放，不在这里做页面状态注册表。
    func invalidateAndReleasePageState()
}

extension SourceExperienceState {
    /// 页面状态默认由 SwiftUI 释放；有额外非视图状态的来源才覆盖。
    func invalidateAndReleasePageState() {}

    /// 切源收尾唯一入口：先失效页面状态，再关闭体验独占资源（§19.4）。
    ///
    /// App Shell 只调用这一个方法，来源不重复实现关闭顺序；图片磁盘缓存由 App 级
    /// `BrowsingImageStore` 持有，不随体验关闭。
    func shutdown() async {
        invalidateAndReleasePageState()
        await resources.close()
    }
}

/// 来源 UI 组合：每个来源在 App 内唯一的体验装配点。
///
/// 契约覆盖体验根视图、本源 destination 构建与跨来源跳转解析；
/// 跨源身份映射（浏览 route）随对应业务页面一起加入。
@MainActor
protocol SourceExperienceModule {
    associatedtype Services: ComicSourceRuntime
    associatedtype Tab: SourceTabValue
    associatedtype Route: SourceDetailRoute
    associatedtype Experience: SourceExperienceState
    associatedtype Root: View
    associatedtype Destination: View
    associatedtype SettingsSheet: View

    /// 本源拥有固定的 Services；构造时不发起业务网络请求。
    init()

    /// typed 默认 Tab，避免由另一份 Plugin 重复声明。
    var defaultTab: Tab { get }

    /// 公共组合边界根据该 key 安装本源 Services，三个页面入口不会漏装。
    var servicesKey: WritableKeyPath<EnvironmentValues, Services?> { get }

    /// 来源展示信息与固定 Tab 定义都由 Module 提供。
    var descriptor: SourceDescriptor { get }

    /// 本源页面使用的稳定 Services；注册项从此取得 Catalog 的同一份能力视图。
    var services: Services { get }

    /// 本源账号访问事实；用于根页面按登录态着色。匿名来源显式返回 `nil`。
    var accountAccess: (any SourceAccessProvider)? { get }

    /// 构建本次激活的体验状态；体验独占资源随本次激活创建并在切源时释放。
    func makeExperience(navigation: SourceNavigationState, resources: ExperienceResources) -> Experience

    /// 构建体验根视图（TabBar 容器）；构造时不发起网络请求。
    func makeRoot(experience: Experience) -> Root

    /// 本源在线内容的访问要求；二级页由公共边界套用，Tab 侧引用同一份本源规则。
    ///
    /// 默认公开。需要登录的来源返回带登录入口的 `.authenticated(...)`；
    /// 只有本源内「默认要求不同」的入口（例如本地书架）才在该入口单独声明例外，
    /// 不在每个 route 上重复判断。离线页面由 `usesLocalAssetsOnly` 自动放行，与此无关。
    var defaultAccessRequirement: SourceAccessRequirement { get }

    /// 构建本源 route 对应的页面（含跨来源 push 进来的本源 route）。
    ///
    /// 只返回本源内容；Services、展示信息、账号事实与图片会话由公共边界安装，
    /// 访问门禁也由公共 `destination(for:)` 统一套上，来源不重复接线。
    func makeDestination(for route: Route) -> Destination

    /// 构建本源设置弹窗内容；由 App 级 sheet 路由在最外层呈现（§8.3）。
    ///
    /// 来源只提供自己的分页与内容，「通用设置」由公共 `SourceSettingsSheet` 固定追加在最后。
    func makeSettingsSheet() -> SettingsSheet

    /// 把公共跳转目标解析成本源 typed route（跨来源跳转用）。
    ///
    /// 只返回本源路由；`AnySourceRoute` 容器由 `SourcePlugin` 统一包装，来源不接触擦除类型。
    func resolve(_ link: SourceLink) throws -> Route

    /// 把一条收藏的检索维度还原成本源的列表页路由。
    ///
    /// 公共层不认识 payload 的结构，只有来源知道自己存了什么；解码失败代表收藏来自旧版本或已损坏。
    func resolve(_ bookmark: Bookmark) throws -> Route
}

extension SourceExperienceModule {
    /// 未声明时本源所有页面公开，来源不需要写任何门禁代码。
    var defaultAccessRequirement: SourceAccessRequirement {
        .publicContent
    }

    /// 体验根复用本次激活的图片会话与工作域；来源只补充本源独有的体验状态。
    ///
    /// 账号访问事实安装到根环境（供根页面头像着色），并在根激活时触发一次静默恢复，
    /// 让公开入口也能反映登录态；恢复任务由账号 owner 去重，重复触发不重复读取。
    func root(experience: Experience) -> some View {
        makeRoot(experience: experience)
            .environment(servicesKey, services)
            .environment(\.sourceDescriptorStorage, descriptor)
            .environment(\.sourceAccountAccess, accountAccess)
            .environment(\.browsingImageServiceStorage, experience.browsingImages)
            .environment(\.browsingImageScopeStorage, experience.resources.browsingImageScope)
            .environment(\.readerSessionScopeStorage, experience.resources.readerSessions)
            .task {
                await accountAccess?.ensureRestored()
            }
    }

    /// 二级页与设置各持有自己的图片画质快照，不继承发起方来源的服务。
    ///
    /// 门禁放在公共边界，规则只有两条：离线页面只读本机资产，直接放行；
    /// 其余页面沿用来源声明一次的统一要求。来源不写门禁代码，
    /// 跨来源 push 与本源 push 也不会走出两套规则。
    func destination(for route: Route) -> some View {
        SourceAccessGate(requirement: route.usesLocalAssetsOnly ? .publicContent : defaultAccessRequirement) {
            makeDestination(for: route)
        }
        .modifier(SourcePageEnvironment(module: self))
    }

    /// 把擦除后的路由按本源 typed route 解包并构建页面。
    ///
    /// 来源自己负责解包，宿主与 Plugin 不接触具体 `Route` 类型；
    /// 宿主只会按 `sourceID` 把本源路由交给本源 Module，类型不匹配属于装配错误。
    func destination(for route: AnySourceRoute) -> AnyView {
        guard let typedRoute = route.routeValue as? Route else {
            preconditionFailure("来源路由与 Module 不匹配：\(route)")
        }

        return AnyView(destination(for: typedRoute))
    }

    func settingsSheet() -> some View {
        makeSettingsSheet()
            .modifier(SourcePageEnvironment(module: self))
    }

    /// 默认实现：详情目标且身份属于本源时构造本源路由；书签收藏交给来源自己的解码实现；否则拒绝。
    ///
    /// 详情语义各来源一致，因此共用一份实现；新增跳转语义时在这里加 case，
    /// 需要额外校验或特殊页面的来源可以自行实现本方法覆盖。
    func resolve(_ link: SourceLink) throws -> Route {
        switch link {
        case let .detail(route):
            guard route.identity.sourceID == services.sourceID, !route.identity.comicID.isEmpty else {
                throw ComicSourceError.invalidIdentity
            }

            return Route.detail(route)

        case let .bookmark(bookmark):
            guard bookmark.sourceID == services.sourceID else {
                throw ComicSourceError.invalidIdentity
            }

            return try resolve(bookmark)
        }
    }
}

/// 安装本源依赖，并让轻量图片解析会话随页面身份保持稳定。
/// 初始化只读取本地画质快照，不启动网络；图片工作域由体验或弹窗 owner 持有。
private struct SourcePageEnvironment<Module: SourceExperienceModule>: ViewModifier {
    let module: Module
    @State private var images: any ComicImageService

    init(module: Module) {
        self.module = module
        _images = State(initialValue: module.services.makeBrowsingImages())
    }

    func body(content: Content) -> some View {
        content
            .environment(module.servicesKey, module.services)
            .environment(\.sourceDescriptorStorage, module.descriptor)
            .environment(\.sourceAccountAccess, module.accountAccess)
            .environment(\.browsingImageServiceStorage, images)
    }
}

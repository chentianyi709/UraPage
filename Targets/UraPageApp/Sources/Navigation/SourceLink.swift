/// 跨来源跳转目标：发起方只提供公共语义值，由目标来源自行解析成本源路由。
///
/// 宿主与导航容器按 `sourceID` 找来源，不保存页面清单；新增一种跨来源语义时
/// 在这里加 case（编译器穷尽提醒），并让 `SourceExperienceModule.resolve(_:)` 处理它。
nonisolated enum SourceLink: Sendable {
    /// 打开漫画详情；身份自带 `sourceID`。
    case detail(ComicDetailRoute)

    /// 打开某来源的标签／作者／分类作品列表；书签自带 `sourceID` 与来源私有身份。
    case bookmark(Bookmark)

    /// 目标来源标识；宿主据此查表。
    var sourceID: ComicSourceID {
        switch self {
        case let .detail(route):
            route.identity.sourceID
        case let .bookmark(entry):
            entry.sourceID
        }
    }

    /// 打开在线详情。
    static func detail(_ identity: ComicIdentity) -> Self {
        .detail(ComicDetailRoute(identity: identity, mode: .online))
    }

    /// 打开同一详情页面并从下载快照读取。
    static func detail(_ identity: ComicIdentity, mode: ComicContentMode) -> Self {
        .detail(ComicDetailRoute(identity: identity, mode: mode))
    }
}

/// 详情 route 的稳定输入；在线／离线只决定数据读取方式，不决定页面类型或布局。
nonisolated struct ComicDetailRoute: Hashable, Sendable {
    let identity: ComicIdentity
    let mode: ComicContentMode
}

/// 带"详情"页面的来源路由。
///
/// 各来源的详情语义一致（漫画身份 → 详情页），因此 `SourceExperienceModule.resolve(_:)`
/// 的默认实现可直接用它；来源只需将相同 route 输入交给自己的详情页面。
nonisolated protocol SourceDetailRoute: SourceRouteValue {
    /// 用完整详情输入构造本源路由。
    static func detail(_ route: ComicDetailRoute) -> Self

    /// 该路由是否只读取本机下载资产（离线详情／离线阅读）。
    ///
    /// 公共 destination 边界只看这一个事实放行离线页面，来源不需要逐页声明门禁。
    /// 默认 `false`：公开来源的所有页面本来就放行，无需实现；
    /// 只有带登录门禁的来源才需要把详情／阅读的 `contentMode` 转发到这里。
    var usesLocalAssetsOnly: Bool { get }
}

extension SourceDetailRoute {
    /// 默认按在线页面处理。
    var usesLocalAssetsOnly: Bool {
        false
    }

    /// 用漫画身份构造在线详情路由。
    static func detail(_ identity: ComicIdentity) -> Self {
        detail(ComicDetailRoute(identity: identity, mode: .online))
    }

    /// 用漫画身份与内容模式构造详情路由。
    static func detail(_ identity: ComicIdentity, mode: ComicContentMode) -> Self {
        detail(ComicDetailRoute(identity: identity, mode: mode))
    }
}

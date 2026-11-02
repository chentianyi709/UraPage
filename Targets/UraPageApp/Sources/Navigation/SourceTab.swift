import Observation

/// 来源 Tab 的公共契约：来源自己声明 Tab 类型，App 层不做来源分派（§19.5）。
///
/// 与 `SourceRouteValue` 同一策略：容器与宿主只保存擦除后的值，
/// 需要 typed Tab 时由本源页面自己还原。
nonisolated protocol SourceTabValue: Hashable, Sendable {
    /// 本源稳定标识；用于装配校验（默认 Tab 必须属于本源）。
    var sourceID: ComicSourceID { get }

    /// TabBar 展示标题。
    var title: String { get }

    /// TabBar 展示图标（SF Symbol 名）。
    var systemImage: String { get }
}

/// 来源 Tab 的类型擦除容器。
///
/// App Shell 只保存与比较它，不解释具体来源的 Tab 内容；每来源一个 typed Tab，
/// 新增来源不需要修改本文件或任何 App 公共类型。
nonisolated struct SourceTab: Hashable, Sendable {
    private let value: any SourceTabValue

    /// 本源稳定标识。
    var sourceID: ComicSourceID {
        value.sourceID
    }

    /// 供本源页面还原 typed Tab；类型不符属于装配错误。
    var tabValue: any SourceTabValue {
        value
    }

    init(_ value: some SourceTabValue) {
        self.value = value
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        AnyHashable(lhs.value) == AnyHashable(rhs.value)
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(AnyHashable(value))
    }
}

extension SourceTab: CustomStringConvertible {
    /// 日志用描述；只包含 typed Tab 的类型与内容，不含敏感信息。
    var description: String {
        String(describing: value)
    }
}

/// 一个来源的轻量导航状态；切源时保留，用于恢复 Tab 与各 Tab 的路径。
///
/// 只保存 route identity 级别的值，不保存 ViewModel、DTO、Services 或已加载数据（§8.2）。
@MainActor
@Observable
final class SourceNavigationState {
    var selectedTab: SourceTab

    /// 每个 Tab 一个导航栈；首次访问时创建，切源后保留。
    @ObservationIgnored private var routers: [SourceTab: AppRouter] = [:]

    init(selectedTab: SourceTab) {
        self.selectedTab = selectedTab
    }

    /// 返回指定 Tab 的导航栈（唯一 owner）。
    func router(for tab: SourceTab) -> AppRouter {
        if let existing = routers[tab] {
            return existing
        }

        let created = AppRouter()
        routers[tab] = created
        return created
    }

    /// 使本来源所有 Tab 的导航锚点失效；切源事务用它丢弃旧体验发起、尚未落地的异步导航。
    func invalidateAnchors() {
        for router in routers.values {
            router.invalidateAnchors()
        }

        AppLogger.debug("导航锚点失效，Tab 数=\(routers.count)", category: "Navigation")
    }
}

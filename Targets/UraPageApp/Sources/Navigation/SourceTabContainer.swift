import SwiftUI

/// 来源体验的 TabBar 容器（§19.3 复用）。
///
/// Tab 结构、每 Tab 的导航栈承载与 Tab 选择绑定只实现一次；来源只提供 typed Tab 的页面映射。
/// `SourceTab` 与 typed Tab 之间的还原（含装配错误暴露）集中在这里，
/// 各来源 RootView 不再复制这段逻辑。
struct SourceTabContainer<TabValue, TabContent>: View
    where
    TabValue: SourceTabValue & CaseIterable & Identifiable,
    TabValue.AllCases: RandomAccessCollection,
    TabValue.ID == TabValue,
    TabContent: View {
    /// App Shell 持有的轻量导航状态（当前 Tab 与各 Tab 的栈）。
    let navigation: SourceNavigationState

    /// 每个 Tab 的访问声明；公开内容与需登录都走同一个门禁入口。
    let accessRequirement: @MainActor (TabValue) -> SourceAccessRequirement

    /// 每个 Tab 的根页面；由来源提供。
    let tabRoot: (TabValue) -> TabContent

    init(
        navigation: SourceNavigationState,
        accessRequirement: @escaping @MainActor (TabValue) -> SourceAccessRequirement = { _ in
            .publicContent
        },
        @ContentBuilder tabRoot: @escaping (TabValue) -> TabContent,
    ) {
        self.navigation = navigation
        self.accessRequirement = accessRequirement
        self.tabRoot = tabRoot
    }

    var body: some View {
        TabView(selection: selection) {
            ForEach(TabValue.allCases) { tab in
                Tab(tab.title, systemImage: tab.systemImage, value: tab) {
                    // 每个 Tab 的栈由公共容器承载，页面映射仍归本来源。
                    AppNavigationStack(router: navigation.router(for: SourceTab(tab))) {
                        SourceAccessGate(requirement: accessRequirement(tab)) {
                            tabRoot(tab)
                        }
                    }
                }
            }
        }
    }

    /// Tab 选择由 App Shell 的轻量导航状态持有，切源后恢复。
    private var selection: Binding<TabValue> {
        Binding(
            get: {
                guard let tab = navigation.selectedTab.tabValue as? TabValue else {
                    // 装配错误：App Shell 只会为本来源体验注入本源 typed Tab。
                    preconditionFailure("体验收到其他来源的 Tab：\(navigation.selectedTab)")
                }

                return tab
            },
            set: { navigation.selectedTab = SourceTab($0) },
        )
    }
}

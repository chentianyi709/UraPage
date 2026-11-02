import SwiftUI

/// 绅士体验根视图：固定 TabBar 容器。
///
/// 各 Tab 的导航栈由 `AppNavigationStack` 统一承载，来源只提供根页面。
struct ShenshiRootView: View {
    let experience: ShenshiExperience

    var body: some View {
        SourceTabContainer(navigation: experience.navigation) { (tab: ShenshiTab) in
            ShenshiTabRootContent(experience: experience, tab: tab)
        }
    }
}

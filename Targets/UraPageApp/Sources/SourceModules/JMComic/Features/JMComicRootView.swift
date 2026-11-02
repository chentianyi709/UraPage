import SwiftUI

/// 禁漫体验根视图：固定 TabBar 容器。
///
/// Tab 结构、栈承载与选择绑定由公共 `SourceTabContainer` 统一处理；
/// 本源只负责把每个 Tab 映射到页面（`JMComicTabRoot`）。
struct JMComicRootView: View {
    let experience: JMComicExperience

    var body: some View {
        SourceTabContainer(navigation: experience.navigation) { (tab: JMComicTab) in
            JMComicTabRootContent(experience: experience, tab: tab)
        }
    }
}

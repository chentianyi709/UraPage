import SwiftUI

/// 当前激活的来源体验：体验状态、轻量导航与其根视图。
///
/// 根视图在这里做类型擦除：各来源的 `Root` 是不同具体类型，宿主只能保存统一入口；
/// 除此之外不使用 `AnyView`，来源页面在各自模块内仍保持静态类型。
@MainActor
final class ActiveSourceExperience {
    let sourceID: ComicSourceID
    let state: any SourceExperienceState

    /// 该来源的轻量导航状态（当前 Tab 与各 Tab 的导航栈）；切源时保留，不随体验销毁。
    let navigation: SourceNavigationState

    /// 激活时构造一次的根视图值；其 body 仍随 SwiftUI 状态正常更新。
    let root: AnyView

    init(
        sourceID: ComicSourceID,
        state: any SourceExperienceState,
        navigation: SourceNavigationState,
        root: AnyView,
    ) {
        self.sourceID = sourceID
        self.state = state
        self.navigation = navigation
        self.root = root
    }
}

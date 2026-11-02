/// 绅士本次激活的体验状态；持有导航、图片工作域与本源筛选登记。
@MainActor
final class ShenshiExperience: SourceExperienceState {
    /// App Shell 持有的轻量导航状态（Tab 选择）。
    let navigation: SourceNavigationState

    /// 本次激活独占的资源（图片工作域）。
    let resources: ExperienceResources

    /// 本次体验共享的普通图片会话；在体验组合边界只创建一次。
    let browsingImages: any ComicImageService

    /// 本源的列表筛选登记（当前由首页分区标题发起）：登记待消费筛选，目标「更新」页消费；由本源独占，不跨来源共享。
    let listFilterHandoff = ShenshiListFilterHandoff()

    init(
        navigation: SourceNavigationState,
        resources: ExperienceResources,
        browsingImages: any ComicImageService,
    ) {
        self.navigation = navigation
        self.resources = resources
        self.browsingImages = browsingImages
    }
}

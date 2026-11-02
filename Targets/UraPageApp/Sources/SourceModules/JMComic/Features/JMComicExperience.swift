/// 禁漫本次激活的体验状态；持有导航、图片工作域与本源筛选交接。
@MainActor
final class JMComicExperience: SourceExperienceState {
    /// App Shell 持有的轻量导航状态（Tab 选择）。
    let navigation: SourceNavigationState

    /// 本次激活独占的资源（图片工作域）。
    let resources: ExperienceResources

    /// 本次体验共享的普通图片会话；在体验组合边界只创建一次。
    let browsingImages: any ComicImageService

    /// 本源的列表筛选登记（当前由首页分区标题发起）：登记待消费分类，目标「分类」页消费；由本源独占，不跨来源共享。
    let listFilterHandoff = JMComicListFilterHandoff()

    /// 本源 Services 由 `JMComicModule` 安装到 Environment（`\.jmComicServices`），体验不重复持有。
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

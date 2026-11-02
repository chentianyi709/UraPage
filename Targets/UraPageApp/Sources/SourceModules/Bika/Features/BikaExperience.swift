/// 哔咔本次激活的体验状态；持有导航与图片工作域。
@MainActor
final class BikaExperience: SourceExperienceState {
    /// App Shell 持有的轻量导航状态（Tab 选择）。
    let navigation: SourceNavigationState

    /// 本次激活独占的资源（图片工作域）。
    let resources: ExperienceResources

    /// 本次体验共享的普通图片会话；在体验组合边界只创建一次。
    let browsingImages: any ComicImageService

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

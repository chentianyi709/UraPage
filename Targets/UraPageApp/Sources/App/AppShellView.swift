import SwiftUI

/// App 根视图：展示当前来源体验，并承载来源切换弹窗。
///
/// 模型由组合根（`AppDependencies`）创建并持有唯一实例：既不在这里现场构造
/// （视图重建会随之造出被 `@State` 丢弃的模型，并连带建出多余的体验与图片工作域），
/// 也不依赖 `@State` 保活。默认来源体验由 `AppShellModel.init` 同步构建，
/// 启动首帧就是来源 TabBar；只有切源释放旧体验、新体验尚未提交的瞬间没有体验可展示。
struct AppShellView: View {
    let model: AppShellModel

    /// 构建 push 目标页面的来源宿主；与模型使用同一个实例。
    let host: AppSourceHost

    /// 通用设置的外观偏好 owner；在这里应用到整个 App（含 App 级弹窗）。
    let appearanceSettings: AppearanceSettingsStore

    /// 通用设置的图片缓存 owner；通用设置页读取（占用／清除／上限）。
    let imageCacheSettings: ImageCacheSettingsStore

    /// 通用设置的阅读历史保留时间 owner；通用设置页读取。
    let readingHistorySettings: ReadingHistorySettingsStore

    /// 通用设置的下载并发 owner；通用设置页读取。
    let downloadSettings: DownloadSettingsStore

    /// 真实系统外观；「跟随系统」时作为弹窗的显式外观值。
    ///
    /// 在本视图读取而不是在 `App` 里读：`App` 上读不到 scene 的真实系统外观（拿到的是默认浅色），
    /// 而 `preferredColorScheme` 只写它**内容**的环境、不写自身，所以这里读到的是被覆盖前的系统外观。
    @Environment(\.colorScheme) private var systemColorScheme

    var body: some View {
        ZStack {
            if let root = model.activeExperience?.root {
                root
                    // 环境引用组合根持有的同一实例；切源与页面动作都写到这个对象上。
                    .environment(\.appShellStorage, AppShellEnvironment(model: model, host: host))
                    .environment(\.sourcePresentationStorage, model)
                    .environment(\.sourceDestinationResolverStorage, host)
                    .environment(\.appearanceSettingsStorage, appearanceSettings)
                    .environment(\.hidesComicCardSubtitles, appearanceSettings.hidesComicCardSubtitles)
                    .environment(\.imageCacheSettingsStorage, imageCacheSettings)
                    .environment(\.readingHistorySettingsStorage, readingHistorySettings)
                    .environment(\.downloadSettingsStorage, downloadSettings)
            }
        }
        // 全局外观＝设置里的主题模式：指定模式时强制，`跟随系统`时保持 `nil` 交还系统原生跟随
        // （显式写系统当前值会把窗口外观钉住，之后系统外观变化不再生效）。
        .preferredColorScheme(appearanceSettings.themeMode.colorScheme)
        .sheet(item: presentedSheetBinding) { route in
            sheetContent(for: route)
                .environment(\.appearanceSettingsStorage, appearanceSettings)
                .environment(\.hidesComicCardSubtitles, appearanceSettings.hidesComicCardSubtitles)
                .environment(\.imageCacheSettingsStorage, imageCacheSettings)
                .environment(\.readingHistorySettingsStorage, readingHistorySettings)
                .environment(\.downloadSettingsStorage, downloadSettings)
                // 弹窗是独立 presentation：主题要显式应用（改完主题立刻可见），
                // 且 `跟随系统`要用具体值才能从深色降级回来（`nil` 在已呈现的弹窗里不降级）。
                .preferredColorScheme(appearanceSettings.themeMode.colorScheme ?? systemColorScheme)
        }
        .background {
            // Toast 使用当前 Scene 的独立 Window，因此不会被 Sheet 遮挡。
            ToastWindowInstaller()
                .frame(width: 0, height: 0)
        }
    }

    /// `sheet(item:)` 的展示绑定：读当前 route；系统关闭（下滑／×）只写回 nil。
    private var presentedSheetBinding: Binding<AppSheetRoute?> {
        Binding(get: { model.presentedSheet }, set: { _ in model.dismissSheet() })
    }

    /// App 级 Sheet 内容；由 `AppSheetRoute` 决定。弹窗外观由各弹窗自己声明。
    @ContentBuilder
    private func sheetContent(for route: AppSheetRoute) -> some View {
        switch route {
        case .sourceSelection:
            SourceSelectionSheet(
                sources: model.descriptors,
                currentSourceID: model.activeExperience?.sourceID,
                isSwitching: model.isSwitchingSource,
                onSelect: { sourceID in
                    Task { await model.switchSource(to: sourceID) }
                },
                onMove: model.moveSources,
            )

        case let .sourceSettings(sourceID):
            host.settingsSheet(for: sourceID)
                // 来源设置里的图片环境切换由公共能力取消当前体验的在途图片请求；
                // 来源只负责在切换成功后调用，不接触图片工作域或 App Shell 类型。
                .environment(\.sourceImageRequestInvalidationStorage, model)
        }
    }
}

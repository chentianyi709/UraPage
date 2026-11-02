import Foundation
import Observation
import SwiftUI

/// 进程级界面偏好 owner：主题模式、卡片副标题显示与章节弹窗布局。
///
/// 读取持久化值、按选择写回；App 根视图读它应用 `preferredColorScheme` 并把
/// `hidesComicCardSubtitles` 装进环境供卡片读取，通用设置页读它展示与修改。
@MainActor
@Observable
final class AppearanceSettingsStore {
    private(set) var themeMode: ThemeMode
    private(set) var hidesComicCardSubtitles: Bool
    private(set) var chapterSheetColumnCount: Int

    @ObservationIgnored private let userDefaults = UserDefaults.standard

    init() {
        themeMode = userDefaults.storedRawRepresentable(
            forKey: AppConfiguration.Storage.themeMode,
            default: .system,
        )
        hidesComicCardSubtitles = userDefaults.storedValue(
            forKey: AppConfiguration.Storage.hidesComicCardSubtitles,
            default: false,
        )
        chapterSheetColumnCount = userDefaults.storedValue(
            forKey: AppConfiguration.Storage.chapterSheetColumnCount,
            default: 3,
        )
    }

    /// 选择主题模式并写回持久化值。
    func select(_ mode: ThemeMode) {
        themeMode = mode
        userDefaults.set(mode.rawValue, forKey: AppConfiguration.Storage.themeMode)
    }

    /// 设置是否隐藏卡片副标题；只显示标题，标题固定占用两行。
    func setHidesComicCardSubtitles(_ hides: Bool) {
        hidesComicCardSubtitles = hides
        userDefaults.set(hides, forKey: AppConfiguration.Storage.hidesComicCardSubtitles)
    }

    /// 所有来源的章节弹窗共用布局，切换时立即保存供下次打开使用。
    func selectChapterSheetColumnCount(_ count: Int) {
        chapterSheetColumnCount = count
        userDefaults.set(count, forKey: AppConfiguration.Storage.chapterSheetColumnCount)
    }
}

extension EnvironmentValues {
    /// 通用设置的界面偏好 owner 存储槽；写入用 `\.appearanceSettingsStorage`（写入路径先读缺省，缺省必须可读）。
    @Entry var appearanceSettingsStorage: AppearanceSettingsStore?

    /// 读取入口：由 App 根视图安装，通用设置页读取，未安装即暴露装配错误。
    var appearanceSettings: AppearanceSettingsStore {
        guard let appearanceSettingsStorage else {
            preconditionFailure("appearanceSettings 未安装：读取通用设置必须位于 App 根边界内")
        }

        return appearanceSettingsStorage
    }

    /// 卡片是否隐藏副标题；由 App 根视图按用户设置安装，`ComicCardView` 读取。
    ///
    /// 这是逐帧渲染要用的展示状态（同 `colorScheme`），因此走环境而不是让卡片读配置。
    @Entry var hidesComicCardSubtitles = false
}

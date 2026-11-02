import Foundation
import Observation
import SwiftUI

/// 三来源共用的阅读显示偏好 owner；只负责设置读写，不持有阅读进度。
/// 简单设置直接赋值即可：Observation 通知界面，didSet 将变更保存到对应 key。
@MainActor
@Observable
final class ReaderSettingsStore {
    var themeMode: ThemeMode {
        didSet {
            defaults.set(themeMode.rawValue, forKey: AppConfiguration.Storage.readerThemeMode)
        }
    }

    var chromeToggleMode: ReaderChromeToggleMode {
        didSet {
            defaults.set(chromeToggleMode.rawValue, forKey: AppConfiguration.Storage.readerChromeToggleMode)
        }
    }

    var disablesSwipeBackWhenChromeHidden: Bool {
        didSet {
            defaults.set(
                disablesSwipeBackWhenChromeHidden,
                forKey: AppConfiguration.Storage.disablesReaderSwipeBackWhenChromeHidden,
            )
        }
    }

    @ObservationIgnored private let defaults = UserDefaults.standard

    init() {
        // 初始化只恢复已保存值，不触发 didSet，不把默认值提前写入持久化。
        themeMode = defaults.storedRawRepresentable(
            forKey: AppConfiguration.Storage.readerThemeMode,
            default: .system,
        )
        chromeToggleMode = defaults.storedRawRepresentable(
            forKey: AppConfiguration.Storage.readerChromeToggleMode,
            default: .doubleTap,
        )
        disablesSwipeBackWhenChromeHidden = defaults.storedValue(
            forKey: AppConfiguration.Storage.disablesReaderSwipeBackWhenChromeHidden,
            default: false,
        )
    }
}

extension EnvironmentValues {
    /// Reader 设置存储槽；写入用 `\.readerSettingsStorage`（写入路径先读缺省，缺省必须可读）。
    @Entry var readerSettingsStorage: ReaderSettingsStore?

    /// 读取入口：由 App 入口安装，未安装即暴露装配错误。
    var readerSettings: ReaderSettingsStore {
        guard let readerSettingsStorage else {
            preconditionFailure("Reader 设置未由 App 入口安装")
        }

        return readerSettingsStorage
    }
}

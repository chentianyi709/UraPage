import SwiftUI

/// App 可以选择的全局浅色／深色外观策略。
///
/// 与旧项目一致：设置页展示 `title`，App 根视图用 `colorScheme` 应用（`nil` 表示继续跟随系统）。
enum ThemeMode: String, CaseIterable, Identifiable {
    /// 跟随系统外观。
    case system

    /// 始终浅色。
    case light

    /// 始终深色（设置页称「黑暗模式」）。
    case dark

    var id: String {
        rawValue
    }

    /// 设置页面展示的模式名称。
    var title: String {
        switch self {
        case .system:
            "跟随系统"
        case .light:
            "浅色模式"
        case .dark:
            "黑暗模式"
        }
    }

    /// 转换为根视图需要的颜色模式；`nil` 表示继续跟随系统。
    var colorScheme: ColorScheme? {
        switch self {
        case .system:
            nil
        case .light:
            .light
        case .dark:
            .dark
        }
    }
}

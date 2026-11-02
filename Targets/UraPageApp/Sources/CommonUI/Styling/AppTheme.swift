import SwiftUI
import UIKit

/// 通用主题色板的唯一定义处。
///
/// 颜色只在这里写一次：数值、浅色/深色取值与用途都集中在本文件，不依赖 Asset Catalog，
/// 改色、加色都只改这一个文件。调用方统一用 `Color.surface` 这类属性取色，
/// 属性名拼写错误是编译错误，不会退化成运行时找不到颜色。
///
/// 颜色随系统外观自动解析（浅色/深色）；将来若需要"更高对比度""降低透明度"等
/// 外观变体，或需要设计工具联动，再考虑迁回 Asset Catalog。
///
/// 约定：数值相同但语义不同的颜色各自保留（例如 `textPrimary` 与 `readerText`、
/// `iconSecondary` 与 `textSecondary`），以便将来分别调整；
/// 只有完全重复且没有独立语义的别名才删除。
extension Color {
    // MARK: - 背景与表面

    /// 页面背景（浅色 #FAFAFA / 深色 #121212）。
    static let pageBackground = Color(light: 0xFAFAFA, dark: 0x121212)

    /// 卡片、列表行与弹窗的表面色（浅色 #FFFFFF / 深色 #1C1C1E）。
    static let surface = Color(light: 0xFFFFFF, dark: 0x1C1C1E)

    /// 抬升表面：浮层、选中态与需要与页面区分的卡片（浅色 #FFFFFF / 深色 #2C2C2E）。
    static let surfaceElevated = Color(light: 0xFFFFFF, dark: 0x2C2C2E)

    /// 中性填充：灰白底的胶囊与轻量控件（浅色 #EBEBEB / 深色 #38383A）。
    /// 与 `divider` 同值但语义不同（填充色 vs 分隔线与描边），按各自用途分别调整。
    static let fillNeutral = Color(light: 0xEBEBEB, dark: 0x38383A)

    /// 阴影色（两种外观均为 #000000，使用方按需叠加透明度）；只用于背景 Shape。
    static let shadow = Color(light: 0x000000, dark: 0x000000)

    /// 卡片阴影：浅色 8% 黑 / 深色 30% 黑（与旧版 `Shadow` 资源一致）；只挂在背景 Shape 上。
    static let cardShadow = Color(light: 0x000000, lightAlpha: 0.08, dark: 0x000000, darkAlpha: 0.30)

    // MARK: - 文本与图标

    /// 主文本（浅色 #1A1A1A / 深色 #FFFFFF）。
    static let textPrimary = Color(light: 0x1A1A1A, dark: 0xFFFFFF)

    /// 次要文本：作者、日期、说明（浅色 #666666 / 深色 #A1A1A6）。
    static let textSecondary = Color(light: 0x666666, dark: 0xA1A1A6)

    /// 三级文本：占位、禁用（浅色 #999999 / 深色 #8E8E93）。
    static let textTertiary = Color(light: 0x999999, dark: 0x8E8E93)

    /// 品牌色底上的文本（浅色 #FFFFFF / 深色 #1A1A1A）。
    static let textOnPrimary = Color(light: 0xFFFFFF, dark: 0x1A1A1A)

    /// 次要图标（浅色 #666666 / 深色 #A1A1A6）。
    static let iconSecondary = Color(light: 0x666666, dark: 0xA1A1A6)

    /// 分隔线与描边（浅色 #EBEBEB / 深色 #38383A）。
    static let divider = Color(light: 0xEBEBEB, dark: 0x38383A)

    // MARK: - 品牌与语义色

    /// 品牌主色（浅色 #B71C1C / 深色 #E57373）：主要按钮与强调文本；
    /// `Assets.xcassets/AccentColor` 与它保持同值，供系统级 accent（Tab 选中态等）使用。
    static let brandPrimary = Color(light: 0xB71C1C, dark: 0xE57373)

    /// 成功（浅色 #2E7D32 / 深色 #66BB6A）。
    static let success = Color(light: 0x2E7D32, dark: 0x66BB6A)

    /// 警告（浅色 #F9A825 / 深色 #FFD54F）。
    static let warning = Color(light: 0xF9A825, dark: 0xFFD54F)

    /// 错误（浅色 #C62828 / 深色 #EF5350）。
    static let error = Color(light: 0xC62828, dark: 0xEF5350)

    // MARK: - Reader

    /// Reader 页面背景（浅色 #F5F5F5 / 深色 #0A0A0A）。
    static let readerBackground = Color(light: 0xF5F5F5, dark: 0x0A0A0A)

    /// Reader 文本（浅色 #1A1A1A / 深色 #FFFFFF）。
    static let readerText = Color(light: 0x1A1A1A, dark: 0xFFFFFF)
}

// MARK: - 构造辅助

private extension Color {
    /// 用浅色/深色两个 sRGB 十六进制值构造随外观变化的颜色。
    ///
    /// 取值交给 `UIColor` 的动态解析，系统外观变化时 SwiftUI 自动刷新；
    /// 因为不经过 Asset Catalog，颜色只需在本文件定义一次。
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            UIColor(rgb: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }

    /// 用浅色/深色两个带透明度的 sRGB 十六进制值构造随外观变化的颜色（用于阴影等半透明色）。
    init(light: UInt32, lightAlpha: CGFloat, dark: UInt32, darkAlpha: CGFloat) {
        self.init(uiColor: UIColor { traits in
            let isDark = traits.userInterfaceStyle == .dark
            return UIColor(rgb: isDark ? dark : light).withAlphaComponent(isDark ? darkAlpha : lightAlpha)
        })
    }
}

private extension UIColor {
    /// 用 0xRRGGBB 构造不透明 sRGB 颜色。
    convenience init(rgb: UInt32) {
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1,
        )
    }
}

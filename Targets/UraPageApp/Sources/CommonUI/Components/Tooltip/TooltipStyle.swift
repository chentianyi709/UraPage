import SwiftUI

/// 提示气泡的尺寸、间距与文字测量。
///
/// 宽高与摆位共用同一套公式：卡片实际 frame 由 `cardWidth`／`cardHeight` 给出，
/// 定位层也用同样的值算 offset，动态字号下不会各算一套。
enum TooltipMetrics {
    /// 脚注默认字号；`@ScaledMetric` 以它为基准，卡片宽高与文字都从缩放后的值算。
    static let baseFontSize: CGFloat = 13

    /// 圆角：贴近 iOS 提示气泡的观感，比正方形卡片略收一点。
    static let cornerRadius: CGFloat = 12
    static let horizontalPadding: CGFloat = 12

    /// 文字与卡片上下边的距离；三角压在卡片边上，这个值同时决定箭头根部离文字多远。
    static let verticalPadding: CGFloat = 12

    static let arrowWidth: CGFloat = 12
    static let arrowHeight: CGFloat = 6

    /// 三角压进卡片的深度，用来消除接缝处的发丝线。
    static let arrowOverlap: CGFloat = 1

    /// 三角露在卡片外的长度；摆位时这段也要算进锚点与卡片之间的空间。
    static var arrowProtrusion: CGFloat {
        arrowHeight - arrowOverlap
    }

    /// 显隐的淡入淡出时长。
    static let fadeDuration: TimeInterval = 0.18

    /// 气泡与锚点之间的间距；要容得下露在外面的三角。
    static let gap: CGFloat = 2

    /// 气泡与屏幕左右边缘的最小距离。
    static let edgeMargin: CGFloat = 8

    /// 投影：轻一点，只让卡片从背景上浮起来，不抢文字。
    static let shadowRadius: CGFloat = 8
    static let shadowOffsetY: CGFloat = 2
    static let shadowOpacityLight: Double = 0.16
    static let shadowOpacityDark: Double = 0.34

    /// 卡片最小宽度：四个字加左右内边距，与字号同比缩放。
    static func minimumWidth(forFontSize fontSize: CGFloat) -> CGFloat {
        4 * fontSize + 2 * horizontalPadding
    }

    /// 卡片宽度：文字实测宽度与最小宽度取大，再夹到屏幕可用宽度；
    /// 摆位和 `TooltipBubble` 的固定 frame 都只使用这一个结果。
    static func cardWidth(for text: String, fontSize: CGFloat, limit: CGFloat) -> CGFloat {
        let font = UIFont.systemFont(ofSize: fontSize, weight: .medium)
        let textWidth = ceil((text as NSString).size(withAttributes: [.font: font]).width)
        let minimumWidth = minimumWidth(forFontSize: fontSize)
        let maximumWidth = max(minimumWidth, limit)

        return min(max(minimumWidth, textWidth + 2 * horizontalPadding), maximumWidth)
    }

    /// 卡片高度：单行文字行高加两侧内边距，与字号同比缩放。
    static func cardHeight(forFontSize fontSize: CGFloat) -> CGFloat {
        let font = UIFont.systemFont(ofSize: fontSize, weight: .medium)

        return ceil(font.lineHeight) + 2 * verticalPadding
    }
}

/// 朝下的实心三角；朝上的情况由使用方旋转 180°。
struct TooltipArrow: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

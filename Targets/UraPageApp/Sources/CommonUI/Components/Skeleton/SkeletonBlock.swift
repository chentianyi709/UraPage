import SwiftUI

/// 绘制骨架屏共同使用的固定尺寸圆角占位块。
struct SkeletonBlock: View {
    let width: CGFloat?
    let height: CGFloat
    let cornerRadius: CGFloat
    let opacity: Double

    /// 使用指定尺寸创建占位块；不传圆角时默认使用胶囊外观。
    init(
        width: CGFloat? = nil,
        height: CGFloat,
        cornerRadius: CGFloat? = nil,
        opacity: Double = 0.18,
    ) {
        self.width = width
        self.height = height
        self.cornerRadius = cornerRadius ?? height / 2
        self.opacity = opacity
    }

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(Color.textTertiary.opacity(opacity))
            .frame(width: width, height: height)
    }
}

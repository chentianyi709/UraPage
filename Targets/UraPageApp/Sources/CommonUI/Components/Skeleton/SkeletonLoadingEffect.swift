import SwiftUI

extension View {
    /// 为骨架屏添加统一呼吸效果，并关闭交互和无障碍读取。
    func skeletonLoadingEffect() -> some View {
        modifier(SkeletonLoadingEffect())
    }
}

/// 集中管理骨架屏共同使用的加载动画与非交互行为。
///
/// 呼吸用 `TimelineView(.animation)` 按系统时钟直接计算透明度，**不产生任何 SwiftUI 动画事务**：
/// 骨架屏含 `GeometryReader`，只要存在动画（无论是 `animation(_:value:)`、`phaseAnimator`
/// 还是带遮罩的动画层），首次布局 settle 都会被一起插值，表现为整块骨架或遮罩“放大一下”。
/// 直接写透明度就没有可插值的属性，几何完全稳定；视觉与旧版一致（0.85 ↔ 0.5 呼吸，周期 1.8 秒）。
private struct SkeletonLoadingEffect: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let period: Double = 1.8

    func body(content: Content) -> some View {
        if reduceMotion {
            content
                .opacity(0.85)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        } else {
            TimelineView(.animation) { context in
                content.opacity(Self.opacity(at: context.date))
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    /// 0.85 ↔ 0.5 的余弦呼吸曲线。
    private static func opacity(at date: Date) -> Double {
        let progress = date.timeIntervalSinceReferenceDate
            .truncatingRemainder(dividingBy: period) / period
        let pulse = 0.5 - 0.5 * cos(2 * .pi * progress)
        return 0.85 - 0.35 * pulse
    }
}

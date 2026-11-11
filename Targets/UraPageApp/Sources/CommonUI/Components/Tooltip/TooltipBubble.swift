import SwiftUI
import UIKit

/// 贴在锚点旁的小提示气泡：深色圆角卡片＋指向锚点的三角，自绘。
///
/// 不用系统 `popover`：它在自定义 `Layout`（例如详情字段行的 `WrappingFlowLayout`）里会以整行为锚点，
/// 内容宽度也会被压成一字一行的长条。自绘的位置由三项输入算出来：锚点在屏幕中的 frame、
/// 气泡自身尺寸、窗口的 bounds 与安全区——因此可以翻面、可以夹边，不依赖对齐参考线。
///
/// 卡片宽度由使用方按「文字宽度／四个字最小宽度／屏幕可用宽度」统一算好后传入：
/// 摆位和实际卡片必须用同一个值，否则动态字号下估算宽度与卡片最小宽度不一致，靠边时会被裁掉。
/// 文案单行显示，超出可用宽度在卡片内尾部截断；完整原文仍保留在数据层与读屏文案里。
/// 气泡可见时接收点击并回调收起，避免点穿到盖在下面的按钮。
struct TooltipBubble: View {
    /// 箭头在气泡的哪条边：`.bottom` 表示气泡在锚点上方、箭头朝下。
    let arrowEdge: VerticalEdge

    /// 气泡文案。
    let text: String

    /// 箭头尖端在水平方向的位置（相对气泡左边缘）；`nil` 时居中。
    /// 气泡被屏幕边缘挤偏时，靠它让箭头继续指着被点的那段文字。
    var arrowCenterX: CGFloat?

    /// 卡片宽度（不含箭头）；由使用方的摆位计算给出。
    let width: CGFloat

    /// 与卡片宽度使用同一缩放来源的字号。
    let fontSize: CGFloat

    /// 点击气泡时回调；`nil` 时气泡不参与命中。
    var onTap: (() -> Void)?

    /// 深色模式要用更重的投影，否则浅色卡片浮在深色背景上几乎没有立体感。
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Text(text)
            .font(.system(size: fontSize, weight: .medium))
            .foregroundStyle(Color.tooltipForeground)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, TooltipMetrics.horizontalPadding)
            // 上下留白必须对称：只加箭头那一侧会让文字在气泡里偏上，看起来像底部多出一块。
            // 三角压在卡片边上，所以「三角离文字更远」就是把这层上下留白一起加厚。
            .padding(.vertical, TooltipMetrics.verticalPadding)
            // 高度也固定成与摆位同一个公式：箭头位置、翻转判断和实际卡片不会各算一套。
            .frame(
                width: width,
                height: TooltipMetrics.cardHeight(forFontSize: fontSize),
            )
            .background {
                // 卡片与箭头先合成一层再加投影：分开加会在接缝处叠出阴影，加在外层则会把文字也投影。
                // 宽高都由调用方传入：不需要再套 `GeometryReader` 去量自己的尺寸。
                ZStack {
                    RoundedRectangle(cornerRadius: TooltipMetrics.cornerRadius, style: .continuous)
                        .fill(Color.tooltipBackground)

                    TooltipArrow()
                        .fill(Color.tooltipBackground)
                        .frame(width: TooltipMetrics.arrowWidth, height: TooltipMetrics.arrowHeight)
                        // 朝上的情况由使用方旋转 180°。
                        .rotationEffect(.degrees(arrowEdge == .bottom ? 0 : 180))
                        .position(
                            x: arrowX(in: width),
                            y: arrowY(in: TooltipMetrics.cardHeight(forFontSize: fontSize)),
                        )
                }
                .compositingGroup()
                .shadow(
                    color: .black.opacity(shadowOpacity),
                    radius: TooltipMetrics.shadowRadius,
                    y: TooltipMetrics.shadowOffsetY,
                )
            }
            // 气泡是纯展示：点位说明已经在按钮的无障碍标签里，不让它再被读一遍。
            .contentShape(Rectangle())
            .onTapGesture {
                onTap?()
            }
            .accessibilityHidden(true)
    }

    /// 投影浓度：深色模式用更重的黑，否则浅色卡片浮在深色底上几乎看不出层次。
    private var shadowOpacity: Double {
        colorScheme == .dark ? TooltipMetrics.shadowOpacityDark : TooltipMetrics.shadowOpacityLight
    }

    /// 箭头中心的横向位置：默认居中，气泡被边缘挤偏时指向锚点中心；再夹到圆角以内，避免三角挂在弧上。
    private func arrowX(in width: CGFloat) -> CGFloat {
        let halfArrow = TooltipMetrics.arrowWidth / 2
        let lowerBound = TooltipMetrics.cornerRadius + halfArrow
        let upperBound = max(lowerBound, width - TooltipMetrics.cornerRadius - halfArrow)
        let desiredX = arrowCenterX ?? width / 2

        return min(max(desiredX, lowerBound), upperBound)
    }

    /// 箭头中心的纵向位置：贴在卡片外侧的那条边上，压进卡片 1pt 消除接缝发丝线。
    private func arrowY(in height: CGFloat) -> CGFloat {
        let halfArrow = TooltipMetrics.arrowHeight / 2

        return arrowEdge == .bottom
            ? height - TooltipMetrics.arrowOverlap + halfArrow
            : TooltipMetrics.arrowOverlap - halfArrow
    }
}

extension View {
    /// 在本视图外侧弹一颗提示气泡；`text` 为 `nil` 时不显示。
    ///
    /// `arrowEdge` 是**偏好**方向：`.bottom`（默认）表示优先放在上方、箭头朝下。
    /// 上方放不下、下方放得下时自动翻到下方、箭头朝上；两边都放不下时选空间更大的一侧并纵向夹进可视区。
    ///
    /// `topReservedHeight` 是可视区顶部额外让出的高度（例如内联导航栏），由使用方按所在页面传入。
    /// `onDismiss` 为 `nil` 时气泡不参与命中；传入后气泡可见时会消费点击并回调，避免点穿到下方按钮。
    ///
    /// 气泡画在锚点的 overlay 上：如果它可能翻到锚点下方、而下方还有同层的兄弟视图，
    /// 需要把锚点所在视图提到上层（`.zIndex`），否则气泡会被兄弟盖住。
    func tooltip(
        _ text: String?,
        arrowEdge: VerticalEdge = .bottom,
        topReservedHeight: CGFloat = 0,
        onDismiss: (() -> Void)? = nil,
    ) -> some View {
        modifier(
            TooltipModifier(
                text: text,
                preferredArrowEdge: arrowEdge,
                topReservedHeight: topReservedHeight,
                onDismiss: onDismiss,
            ),
        )
    }
}

/// 负责把气泡摆到锚点外侧。
///
/// 不用 `alignmentGuide` 推位置：它套在 overlay 的 `if` 分支里会被忽略（实测气泡会落在锚点上、
/// 压住字段）。改为量出锚点与气泡的尺寸后自己算位置：
/// - 纵向优先放偏好方向，只有该侧真正放得下才用；否则翻到另一侧，两侧都放不下就选空间更大的一侧；
/// - 横向先居中，再夹进屏幕左右安全边距；被挤偏时把偏差交给箭头，箭头始终指着锚点中心。
private struct TooltipModifier: ViewModifier {
    let text: String?
    let preferredArrowEdge: VerticalEdge

    /// 可视区顶部额外让出的高度，由使用方按页面导航栏配置。
    let topReservedHeight: CGFloat

    /// 气泡可见时点击收起；`nil` 时气泡不参与命中。
    let onDismiss: (() -> Void)?

    /// 与气泡卡片共用同一缩放来源的字号；宽度、高度都由它算出来。
    @ScaledMetric(relativeTo: .footnote) private var fontSize: CGFloat = TooltipMetrics.baseFontSize

    /// 锚点在屏幕坐标系里的位置；由 `.global` 读出，滚动时会跟着更新。
    @State private var anchorFrame: CGRect = .zero

    /// 窗口的 bounds 与安全区。只支持竖屏、生命周期内不变，出现时读一次即可，
    /// 避免滚动时 `anchorFrame` 每帧变化都去遍历 scene／window。
    @State private var windowGeometry: WindowGeometry?

    /// 最后一次的文案与位置。消失时 `text`／`placement` 会立刻变 `nil`，
    /// 淡出期间仍要用旧内容与旧位置——否则气泡会一边缩成空壳、一边跳回锚点。
    @State private var lastText: String = ""
    @State private var lastPlacement: Placement?

    func body(content: Content) -> some View {
        let placement = placement
        let effectivePlacement = placement ?? lastPlacement
        let displayedText = text ?? lastText
        let bubbleWidth = effectivePlacement?.width ?? TooltipMetrics.minimumWidth(forFontSize: fontSize)
        let showsBubble = text != nil && placement != nil

        content
            .onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: .global)
            } action: { frame in
                anchorFrame = frame
                // 首帧可能早于 key window 就绪；锚点每次重新布局时补读一次，读到后不再遍历 scene。
                if windowGeometry == nil {
                    windowGeometry = Self.currentWindowGeometry()
                }
            }
            .task {
                guard windowGeometry == nil else { return }

                // 极少数情况下页面先布局、窗口稍后才成为 key window；短轮询兜住这一小段时间。
                for _ in 0 ..< 5 {
                    guard !Task.isCancelled else { return }

                    if let geometry = Self.currentWindowGeometry() {
                        windowGeometry = geometry
                        return
                    }

                    try? await Task.sleep(for: .milliseconds(100))
                }
            }
            .onChange(of: placement) { _, newValue in
                if let newValue {
                    lastPlacement = newValue
                }
            }
            .onChange(of: text) { _, newValue in
                if let newValue {
                    lastText = newValue
                }
            }
            .overlay(alignment: .topLeading) {
                // 不放 `if text != nil` 的分支：overlay 的条件内容会让几何测量不触发，
                // 位置就按「宽度 0」算——短文案看不出来，宽文案会跑到屏幕外。
                TooltipBubble(
                    arrowEdge: effectivePlacement?.arrowEdge ?? preferredArrowEdge,
                    text: displayedText,
                    arrowCenterX: effectivePlacement?.arrowCenterX,
                    width: bubbleWidth,
                    fontSize: effectivePlacement?.fontSize ?? fontSize,
                    onTap: onDismiss,
                )
                .offset(x: effectivePlacement?.x ?? 0, y: effectivePlacement?.y ?? 0)
                // 位置只瞬移、不插值：外层曾用 `withAnimation` 包住状态切换，会把 offset
                // 从 0 动画到目标值，看起来像气泡从字段里「飞」出来。清掉这一层的动画事务。
                .transaction { transaction in
                    transaction.animation = nil
                }
                // 显隐单独做渐隐渐显，不受外层动画影响。
                .opacity(showsBubble ? 1 : 0)
                .animation(.easeInOut(duration: TooltipMetrics.fadeDuration), value: showsBubble)
                // 只有真正可见且提供了收起回调时才拦住点击；淡出/隐藏时不挡下面的按钮。
                .allowsHitTesting(showsBubble && onDismiss != nil)
            }
    }

    /// 当前该怎么摆；窗口或锚点还没就绪时返回 `nil`（这一帧不显示）。
    private var placement: Placement? {
        guard let windowGeometry, !anchorFrame.isEmpty, let text else {
            return nil
        }

        let bounds = windowGeometry.bounds
        let insets = windowGeometry.insets
        // 顶部让出状态栏、使用方指定的导航栏高度与底部安全区。
        let topLimit = bounds.minY + insets.top + topReservedHeight
        let bottomLimit = bounds.maxY - insets.bottom

        let aboveSpace = anchorFrame.minY - topLimit
        let belowSpace = bottomLimit - anchorFrame.maxY
        let bubbleWidth = TooltipMetrics.cardWidth(
            for: text,
            fontSize: fontSize,
            limit: bounds.width - 2 * TooltipMetrics.edgeMargin,
        )
        let bubbleHeight = TooltipMetrics.cardHeight(forFontSize: fontSize)
        // 锚点与卡片之间还要容下露在外面的三角，否则箭头尖端会压进锚点。
        let requiredSpace = bubbleHeight + TooltipMetrics.arrowProtrusion + TooltipMetrics.gap

        let aboveFits = aboveSpace >= requiredSpace
        let belowFits = belowSpace >= requiredSpace
        let showsAbove: Bool
        if preferredArrowEdge == .bottom {
            // 偏好上方；上方放不下时，只有下方真正放得下或确实更宽裕才翻下去。
            showsAbove = aboveFits || (!belowFits && aboveSpace >= belowSpace)
        } else {
            showsAbove = !(belowFits || (!aboveFits && belowSpace >= aboveSpace))
        }

        // 横向先按锚点居中，再夹进屏幕两边，保证气泡整体可见。
        let desiredLeft = anchorFrame.midX - bubbleWidth / 2
        let minLeft = bounds.minX + TooltipMetrics.edgeMargin
        let maxLeft = max(minLeft, bounds.maxX - TooltipMetrics.edgeMargin - bubbleWidth)
        let left = min(max(desiredLeft, minLeft), maxLeft)

        // 纵向按选定的一侧摆放；两边都不够时也要把卡片夹进可视区，宁可箭头偏离锚点。
        let idealTop = showsAbove
            ? anchorFrame.minY - TooltipMetrics.gap - TooltipMetrics.arrowProtrusion - bubbleHeight
            : anchorFrame.maxY + TooltipMetrics.gap + TooltipMetrics.arrowProtrusion
        let maxTop = max(topLimit, bottomLimit - bubbleHeight)
        let top = min(max(idealTop, topLimit), maxTop)

        return Placement(
            arrowEdge: showsAbove ? .bottom : .top,
            x: left - anchorFrame.minX,
            y: top - anchorFrame.minY,
            arrowCenterX: anchorFrame.midX - left,
            width: bubbleWidth,
            fontSize: fontSize,
        )
    }

    /// 气泡要落在哪个窗口坐标系里；`.global` 与窗口坐标一致，单窗口下就是屏幕。
    private static func currentWindowGeometry() -> WindowGeometry? {
        guard let window = UIApplication.shared
            .connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap(\.windows)
            .first(where: \.isKeyWindow) else { return nil }

        return WindowGeometry(bounds: window.bounds, insets: window.safeAreaInsets)
    }

    private struct WindowGeometry {
        let bounds: CGRect
        let insets: UIEdgeInsets
    }

    private struct Placement: Equatable {
        let arrowEdge: VerticalEdge
        let x: CGFloat
        let y: CGFloat
        let arrowCenterX: CGFloat
        let width: CGFloat
        let fontSize: CGFloat
    }
}

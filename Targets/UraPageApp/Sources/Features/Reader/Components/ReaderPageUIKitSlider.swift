import SwiftUI
import UIKit

/// 使用 UIKit 滑块稳定取得拖动结束事件，
/// 避免滑块松手前连续提交 Canvas 跳页；支持点击轨道直接跳页。
struct ReaderPageUIKitSlider: UIViewRepresentable {
    @Binding var value: Double

    let pageTotal: Int
    let onEditingChanged: (Bool) -> Void
    let onEditingCancelled: () -> Void

    /// 创建并连接 UIKit 滑块的值与编辑状态回调。
    func makeUIView(context: Context) -> ReaderPageUIKitSliderView {
        let view = ReaderPageUIKitSliderView()
        view.onValueChange = { newValue in
            guard context.coordinator.value.wrappedValue != newValue else { return }

            context.coordinator.value.wrappedValue = newValue
        }
        view.onEditingChanged = onEditingChanged
        view.onEditingCancelled = onEditingCancelled
        return view
    }

    /// 同步当前页码和章节总页数；
    /// 拖动期间不会覆盖手指位置。
    func updateUIView(
        _ uiView: ReaderPageUIKitSliderView,
        context: Context,
    ) {
        // SwiftUI 可能保留 UIKit View、
        // 同时替换外层 State 存储，因此必须同步最新 Binding。
        context.coordinator.value = $value
        uiView.configure(
            value: value,
            pageTotal: pageTotal,
        )
        uiView.onEditingChanged = onEditingChanged
        uiView.onEditingCancelled = onEditingCancelled
    }

    /// 固定滑块高度，只让外层决定可用宽度。
    static func sizeThatFits(
        _ proposal: ProposedViewSize,
        uiView _: ReaderPageUIKitSliderView,
        context _: Context,
    ) -> CGSize? {
        CGSize(
            width: proposal.width ?? UIView.noIntrinsicMetric,
            height: 31,
        )
    }

    /// 保存 SwiftUI Binding，供 UIKit 值变化时回写。
    func makeCoordinator() -> Coordinator {
        Coordinator(value: $value)
    }

    final class Coordinator {
        var value: Binding<Double>

        init(value: Binding<Double>) {
            self.value = value
        }
    }
}

/// 把连续手势转换为整数页码，
/// 并在跨页时提供轻触反馈。
final class ReaderPageUIKitSliderView: UIView {
    var onValueChange: ((Double) -> Void)?
    var onEditingChanged: ((Bool) -> Void)?
    var onEditingCancelled: (() -> Void)?

    private let slider = UISlider()
    private let hapticGenerator = UISelectionFeedbackGenerator()
    private var range: ClosedRange<Double> = 1 ... 1
    private var lastHapticStep: Int?
    private var isDragging = false

    private var dragStartLocationX: CGFloat?
    private var dragStartValue: Double?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: 31)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        slider.frame = bounds
    }

    /// 更新页码范围和当前值，
    /// 不干扰正在进行的拖动。
    func configure(
        value: Double,
        pageTotal: Int,
    ) {
        let nextRange = 1 ... Double(max(pageTotal, 1))
        if range != nextRange {
            range = nextRange
            slider.minimumValue = Float(range.lowerBound)
            slider.maximumValue = Float(range.upperBound)
        }

        // 拖动后的目标页预览由 Overlay 持有；UIKit 不再保存另一份提交值。
        let snappedValue = snapped(value)
        if !isDragging,
           Double(slider.value) != snappedValue {
            slider.value = Float(snappedValue)
        }
        updateAccessibilityValue()
    }

    /// 安装由外层手势驱动的系统滑块：拖动连续选页，点击轨道直接选页；
    /// 点击 thumb 本身保持当前页。
    private func setupViews() {
        backgroundColor = .clear
        slider.isContinuous = true
        slider.minimumValue = Float(range.lowerBound)
        slider.maximumValue = Float(range.upperBound)
        slider.minimumTrackTintColor = UIColor(.accent)
        slider.maximumTrackTintColor = UIColor.systemGray.withAlphaComponent(0.7)

        // UISlider 自己不处理触摸，
        // 全部交给外层手势。
        slider.isUserInteractionEnabled = false
        addSubview(slider)

        isAccessibilityElement = true
        accessibilityTraits = .adjustable
        accessibilityLabel = "跳转页码"
        updateAccessibilityValue()

        let panGesture = UIPanGestureRecognizer(
            target: self,
            action: #selector(handleSliderPan(_:)),
        )
        addGestureRecognizer(panGesture)

        let tapGesture = UITapGestureRecognizer(
            target: self,
            action: #selector(handleSliderTap(_:)),
        )
        addGestureRecognizer(tapGesture)
    }

    /// 开始一次整数页码选择。
    private func beginEditing() {
        isDragging = true
        lastHapticStep = stepIndex(for: Double(slider.value))
        hapticGenerator.prepare()
        onEditingChanged?(true)
    }

    /// 仅在跨过整数页时同步 SwiftUI 和触觉反馈。
    private func valueChanged() {
        let newValue = snapped(Double(slider.value))
        slider.value = Float(newValue)
        guard lastHapticStep != stepIndex(for: newValue) else { return }

        triggerHapticIfNeeded(for: newValue)
        onValueChange?(newValue)
        updateAccessibilityValue()
    }

    /// 提交拖动结束时的最终整数页码。
    private func endEditing() {
        let newValue = snapped(Double(slider.value))
        slider.value = Float(newValue)
        isDragging = false
        onEditingChanged?(false)
        lastHapticStep = nil
        updateAccessibilityValue()
    }

    /// 限制并四舍五入到当前章节的合法页码。
    private func snapped(_ value: Double) -> Double {
        min(max(value.rounded(), range.lowerBound), range.upperBound)
    }

    /// 返回指定页码对应的触觉反馈步数。
    private func stepIndex(for value: Double) -> Int {
        Int(snapped(value) - range.lowerBound)
    }

    /// 只有跨到新页码时才触发一次选择反馈。
    private func triggerHapticIfNeeded(for value: Double) {
        let nextStep = stepIndex(for: value)
        guard lastHapticStep != nextStep else {
            return
        }

        hapticGenerator.selectionChanged()
        hapticGenerator.prepare()
        lastHapticStep = nextStep
    }

    /// 按拖动起点和位移更新页码，
    /// 手势结束后再通知提交。
    @objc private func handleSliderPan(_ gesture: UIPanGestureRecognizer) {
        switch gesture.state {
        case .began:
            dragStartLocationX = gesture.location(in: slider).x
            dragStartValue = Double(slider.value)
            beginEditing()

        case .changed:
            updateValueRelativeToDragStart(for: gesture)
            valueChanged()

        case .ended:
            updateValueRelativeToDragStart(for: gesture)
            valueChanged()
            endEditing()
            resetDragState()

        case .cancelled, .failed:
            cancelEditing()
            resetDragState()

        default:
            break
        }
    }

    /// 点击轨道时把句柄直接移到点击页，并按一次完整选择提交跳页。
    ///
    /// 点在 thumb 上视为按住当前页，不按最近页跳转；
    /// thumb 比单页槽位宽，按最近页取整会误跳相邻页。
    @objc private func handleSliderTap(_ gesture: UITapGestureRecognizer) {
        let location = gesture.location(in: slider)
        guard !isOverThumb(atX: location.x),
              let targetValue = value(atLocationX: location.x),
              targetValue != snapped(Double(slider.value))
        else {
            return
        }

        beginEditing()
        slider.value = Float(targetValue)
        valueChanged()
        endEditing()
    }

    /// 触点是否落在当前 thumb 的水平范围内。
    private func isOverThumb(atX locationX: CGFloat) -> Bool {
        let trackRect = slider.trackRect(forBounds: slider.bounds)
        let thumb = thumbRect(in: trackRect)
        return abs(locationX - thumb.midX) <= thumb.width / 2
    }

    /// 把轨道上的横坐标映射到页面范围内的值；
    /// 点击与拖动共用 thumb 可移动宽度，保证两种手势的页码换算一致。
    private func value(atLocationX locationX: CGFloat) -> Double? {
        guard range.upperBound > range.lowerBound,
              let travel = thumbTravel()
        else {
            return nil
        }

        let progress = min(
            max((locationX - travel.minX) / travel.width, 0),
            1,
        )
        let value = range.lowerBound
            + Double(progress) * (range.upperBound - range.lowerBound)
        return snapped(value)
    }

    /// 当前值对应的 thumb 绘制矩形。
    private func thumbRect(in trackRect: CGRect) -> CGRect {
        slider.thumbRect(
            forBounds: slider.bounds,
            trackRect: trackRect,
            value: slider.value,
        )
    }

    /// thumb 中心在轨道上的可移动范围；首尾页以 thumb 中心贴住轨道两端。
    private func thumbTravel() -> (minX: CGFloat, width: CGFloat)? {
        let trackRect = slider.trackRect(forBounds: slider.bounds)
        guard trackRect.width > 0 else { return nil }

        let thumbWidth = thumbRect(in: trackRect).width
        let minX = trackRect.minX + thumbWidth / 2
        let width = trackRect.width - thumbWidth
        guard width > 0 else { return nil }

        return (minX, width)
    }

    /// 把手指相对位移映射到完整章节页码范围；
    /// 使用与点击相同的 thumb 可移动宽度，使 thumb 的移动距离与手指保持一致。
    private func updateValueRelativeToDragStart(
        for gesture: UIPanGestureRecognizer,
    ) {
        guard range.upperBound > range.lowerBound,
              let travel = thumbTravel(),
              let dragStartLocationX,
              let dragStartValue
        else {
            return
        }

        let locationX = gesture.location(in: slider).x
        let dragProgress = (locationX - dragStartLocationX) / travel.width
        let nextValue = dragStartValue + Double(dragProgress) * (range.upperBound - range.lowerBound)
        slider.value = Float(
            min(max(nextValue, range.lowerBound), range.upperBound),
        )
    }

    /// 清除本次拖动起点，
    /// 避免下次手势继承旧状态。
    private func resetDragState() {
        dragStartLocationX = nil
        dragStartValue = nil
    }

    /// 系统取消手势时恢复拖动起点，
    /// 不把不完整的位置当成用户提交。
    private func cancelEditing() {
        let restoredValue = snapped(
            dragStartValue ?? Double(slider.value),
        )
        slider.value = Float(restoredValue)
        onValueChange?(restoredValue)
        isDragging = false
        onEditingCancelled?()
        lastHapticStep = nil
        updateAccessibilityValue()
    }

    /// 允许 VoiceOver 使用标准可调整手势向后选择一页。
    override func accessibilityIncrement() {
        adjustPageForAccessibility(by: 1)
    }

    /// 允许 VoiceOver 使用标准可调整手势向前选择一页。
    override func accessibilityDecrement() {
        adjustPageForAccessibility(by: -1)
    }

    /// 把一次无障碍增减作为完整的页码选择并提交。
    private func adjustPageForAccessibility(by offset: Double) {
        let currentValue = snapped(Double(slider.value))
        let newValue = snapped(currentValue + offset)
        guard newValue != currentValue else {
            return
        }

        onEditingChanged?(true)
        slider.value = Float(newValue)
        onValueChange?(newValue)
        updateAccessibilityValue()
        onEditingChanged?(false)
    }

    /// 向 VoiceOver 提供未补零的当前页和总页数。
    private func updateAccessibilityValue() {
        let pageNumber = Int(snapped(Double(slider.value)))
        let pageTotal = Int(range.upperBound)
        let nextValue = "第 \(pageNumber) 页，共 \(pageTotal) 页"
        if accessibilityValue != nextValue {
            accessibilityValue = nextValue
        }
    }
}

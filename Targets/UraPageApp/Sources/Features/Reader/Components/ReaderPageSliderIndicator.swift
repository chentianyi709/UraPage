import SwiftUI

/// 在页码滑块拖动期间于屏幕中央显示目标页。
struct ReaderPageSliderIndicator: View {
    let pageNumber: Int
    let pageTotal: Int

    var body: some View {
        Text(ReaderPageNumberText.padded(pageNumber, total: pageTotal))
            .font(.system(size: 42, weight: .black, design: .rounded))
            .monospacedDigit()
            .contentTransition(.numericText(value: Double(clampedPageNumber)))
            .animation(.snappy(duration: 0.2), value: clampedPageNumber)
            .foregroundStyle(.primary)
            .padding(.horizontal, 32)
            .padding(.vertical, 18)
            .glassEffect(in: .rect(cornerRadius: 18))
            .allowsHitTesting(false)
            .accessibilityLabel("第 \(clampedPageNumber) 页，共 \(pageTotal) 页")
    }

    /// 防止外部状态变化期间显示越界页码。
    private var clampedPageNumber: Int {
        min(max(pageNumber, 1), pageTotal)
    }
}

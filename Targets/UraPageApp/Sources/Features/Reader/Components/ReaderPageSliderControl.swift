import SwiftUI

/// 显示 Reader 当前章节的页码滑块，
/// 并在拖动结束或点击轨道时提交跳页；点击 thumb 本身不提交。
struct ReaderPageSliderControl: View {
    let pageTotal: Int

    @Binding var value: Double
    let onEditingChanged: (Bool) -> Void
    let onCommit: (Int) -> Void

    var body: some View {
        ReaderPageUIKitSlider(
            value: $value,
            pageTotal: pageTotal,
            onEditingChanged: { editing in
                onEditingChanged(editing)
                if !editing {
                    onCommit(currentPageNumber)
                }
            },
            onEditingCancelled: {
                // 被系统中断的手势只结束预览，
                // 不提交中途页码。
                onEditingChanged(false)
            },
        )
        .frame(height: 31)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .glassEffect(in: .capsule)
    }

    /// 返回滑块当前选中的合法页码。
    private var currentPageNumber: Int {
        min(max(Int(value.rounded()), 1), max(pageTotal, 1))
    }
}

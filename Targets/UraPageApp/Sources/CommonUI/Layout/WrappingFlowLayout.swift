import SwiftUI

/// 按自身宽度排列子视图、空间不足时换行的流式布局。
///
/// 详情页的分类／标签与搜索页的热门搜索词都用它排布胶囊。尺寸计算与旧项目
/// `Shared/Components/Layout/WrappingFlowLayout.swift` 一致：**返回父容器给出的宽度**，
/// 没有有限宽度约束时才回退到内容理想总宽——否则父容器会因返回宽度变化反复提案，
/// 形成布局反馈把主线程卡死。
struct WrappingFlowLayout: Layout {
    /// 同一行内的水平间距。
    let horizontalSpacing: CGFloat

    /// 相邻行之间的垂直间距。
    let verticalSpacing: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache _: inout (),
    ) -> CGSize {
        let maximumWidth: CGFloat
        if let proposedWidth = proposal.width, proposedWidth.isFinite {
            maximumWidth = max(proposedWidth, 1)
        } else {
            maximumWidth = max(idealWidth(for: subviews), 1)
        }
        return result(maximumWidth: maximumWidth, subviews: subviews).size
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal _: ProposedViewSize,
        subviews: Subviews,
        cache _: inout (),
    ) {
        let layout = result(maximumWidth: max(bounds.width, 1), subviews: subviews)

        for (index, subview) in subviews.enumerated() {
            let size = layout.sizes[index]
            subview.place(
                at: CGPoint(
                    x: bounds.minX + layout.positions[index].x,
                    y: bounds.minY + layout.positions[index].y,
                ),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: size.width, height: size.height),
            )
        }
    }

    /// 按行排列全部子视图，返回最终尺寸与相对坐标。
    private func result(maximumWidth: CGFloat, subviews: Subviews) -> Result {
        var result = Result()
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let idealSize = subview.sizeThatFits(.unspecified)
            let proposedWidth = min(idealSize.width, maximumWidth)
            let size = subview.sizeThatFits(ProposedViewSize(width: proposedWidth, height: nil))

            if x > 0, x + size.width > maximumWidth {
                x = 0
                y += rowHeight + verticalSpacing
                rowHeight = 0
            }

            result.positions.append(CGPoint(x: x, y: y))
            result.sizes.append(size)
            rowHeight = max(rowHeight, size.height)
            x += size.width + horizontalSpacing
        }

        result.size = CGSize(width: maximumWidth, height: y + rowHeight)
        return result
    }

    /// 父容器没有给出有限宽度时，全部子视图排成一行的理想总宽。
    private func idealWidth(for subviews: Subviews) -> CGFloat {
        subviews.enumerated().reduce(CGFloat.zero) { width, item in
            width
                + (item.offset == 0 ? 0 : horizontalSpacing)
                + item.element.sizeThatFits(.unspecified).width
        }
    }

    /// 一次换行布局计算得到的尺寸、坐标与子视图尺寸。
    private struct Result {
        var size = CGSize.zero
        var positions: [CGPoint] = []
        var sizes: [CGSize] = []
    }
}

import SwiftUI

/// 提供共享文本截断 Renderer 使用的低层绘制与测量方法。
extension TextTruncationTextRenderer {
    /// 在为操作文字预留空间后绘制一行可容纳的文字切片。
    func drawLine(
        _ line: Text.Layout.Line,
        indicator: GraphicsContext.ResolvedText,
        indicatorSize: CGSize,
        in context: inout GraphicsContext,
    ) {
        guard containerWidth > 0 else {
            context.draw(line)
            return
        }

        let lineBounds = line.typographicBounds.rect

        let rightEdge = max(
            containerWidth,
            lineBounds.minX,
        )

        let indicatorReservedX = max(
            lineBounds.minX,
            rightEdge - indicatorSize.width,
        )

        let textEndX = max(
            lineBounds.minX,
            indicatorReservedX - spacing,
        )

        var lastDrawnX = lineBounds.minX

        drawSlices: for run in line {
            for slice in run {
                let sliceBounds = slice.typographicBounds.rect

                guard sliceBounds.maxX <= textEndX else {
                    break drawSlices
                }

                context.draw(slice)
                lastDrawnX = sliceBounds.maxX
            }
        }

        let indicatorX = max(
            lineBounds.minX,
            min(
                max(lastDrawnX + spacing, lineBounds.minX),
                indicatorReservedX,
            ),
        )

        context.draw(
            indicator,
            at: CGPoint(
                x: indicatorX,
                y: lineBounds.midY,
            ),
            anchor: .leading,
        )
    }

    /// 创建使用主题色的操作文字及其排版尺寸。
    func makeIndicator(
        _ value: String,
        context: GraphicsContext,
    ) -> (
        text: GraphicsContext.ResolvedText,
        size: CGSize,
    ) {
        var text = context.resolve(Text(value))
        text.shading = .color(indicatorColor)

        let size = text.measure(
            in: CGSize(
                width: CGFloat.greatestFiniteMagnitude,
                height: CGFloat.greatestFiniteMagnitude,
            ),
        )

        return (text, size)
    }

    /// 把线性进度转换为首尾平滑的渐变进度。
    func smoothStep(_ value: CGFloat) -> CGFloat {
        let value = min(max(value, 0), 1)
        return value * value * (3 - 2 * value)
    }
}

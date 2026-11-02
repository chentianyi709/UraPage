import SwiftUI

/// 分别绘制紧凑摘要与保留换行的原文，展开进度只控制两层的交接。
@Animatable
struct TextTruncationTextRenderer: TextRenderer {
    enum Presentation: Equatable {
        case collapsed
        case expanded
    }

    @AnimatableIgnored var presentation: Presentation
    @AnimatableIgnored var showsIndicator: Bool
    @AnimatableIgnored var length: Int
    @AnimatableIgnored var containerWidth: CGFloat

    var progress: CGFloat

    private let moreText = "展开"

    let indicatorColor: Color = .brandPrimary
    let spacing: CGFloat = 0

    private let blendRange: CGFloat = 0.10

    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        let lines = Array(layout)
        guard !lines.isEmpty else {
            return
        }
        guard showsIndicator else {
            if presentation == .collapsed {
                for line in lines {
                    context.draw(line)
                }
            }
            return
        }

        let blendProgress = smoothStep(min(max(progress, 0), 1) / blendRange)

        switch presentation {
        case .collapsed:
            context.opacity *= Double(1 - blendProgress)

            let visibleLines = lines.prefix(length)
            for line in visibleLines.dropLast() {
                context.draw(line)
            }

            if let lastLine = visibleLines.last {
                let indicator = makeIndicator(moreText, context: context)
                drawLine(
                    lastLine,
                    indicator: indicator.text,
                    indicatorSize: indicator.size,
                    in: &context,
                )
            }

        case .expanded:
            context.opacity *= Double(blendProgress)
            for line in lines {
                context.draw(line)
            }
        }
    }
}

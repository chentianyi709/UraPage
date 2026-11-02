import UIKit

extension ReaderCanvasUIView {
    /// 返回顶部章节边界当前参与滚动范围的固定高度。
    var topBoundaryContentHeight: CGFloat {
        topBoundaryPresentation == nil ? 0 : chapterBoundaryHeight
    }

    /// 返回底部章节边界当前参与滚动范围的固定高度。
    var bottomBoundaryContentHeight: CGFloat {
        bottomBoundaryPresentation == nil ? 0 : chapterBoundaryHeight
    }

    /// 原地更新章节边界状态，不修改漫画页面清单或页面 identity。
    func updateChapterBoundaryPresentations(
        top: ReaderCanvasChapterBoundaryPresentation?,
        bottom: ReaderCanvasChapterBoundaryPresentation?,
    ) {
        let didChangeExtent = (topBoundaryPresentation == nil) != (top == nil)
            || (bottomBoundaryPresentation == nil) != (bottom == nil)
        let didChangePresentation = topBoundaryPresentation != top
            || bottomBoundaryPresentation != bottom

        topBoundaryPresentation = top
        bottomBoundaryPresentation = bottom
        topBoundaryView.configure(
            presentation: top,
            onRetry: onRetryTopBoundary,
        )
        bottomBoundaryView.configure(
            presentation: bottom,
            onRetry: onRetryBottomBoundary,
        )

        guard didChangePresentation else {
            return
        }

        if didChangeExtent {
            clampScrollAnchor()
        }
        resetRenderSignature()
        needsRender = true
    }

    /// 让两个边界占位项跟随真实漫画内容的顶部和底部移动。
    func updateChapterBoundaryFrames(renderedRange: Range<Int>) {
        guard !nodes.isEmpty else {
            topBoundaryView.isHidden = true
            bottomBoundaryView.isHidden = true
            return
        }

        let shouldShowTop = topBoundaryPresentation != nil
            && renderedRange.lowerBound == nodes.startIndex
        topBoundaryView.isHidden = !shouldShowTop
        if shouldShowTop {
            topBoundaryView.frame = CGRect(
                x: 0,
                y: pixelAligned(screenTopY(for: nodes.startIndex) - chapterBoundaryHeight),
                width: bounds.width,
                height: chapterBoundaryHeight,
            )
        }

        let shouldShowBottom = bottomBoundaryPresentation != nil
            && renderedRange.upperBound == nodes.endIndex
        bottomBoundaryView.isHidden = !shouldShowBottom
        if shouldShowBottom {
            let lastIndex = nodes.index(before: nodes.endIndex)
            bottomBoundaryView.frame = CGRect(
                x: 0,
                y: pixelAligned(screenTopY(for: lastIndex) + nodes[lastIndex].height),
                width: bounds.width,
                height: chapterBoundaryHeight,
            )
        }
    }
}

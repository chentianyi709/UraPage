import QuartzCore
import UIKit

extension ReaderCanvasUIView {
    /// 按旧版可见面积与屏幕中心权重选出主页面，并限制状态回报频率。
    func reportCurrentPageIfNeeded(force: Bool = false) {
        guard let node = mostRelevantVisibleNode(),
              reportedCurrentPageID != node.id
        else {
            return
        }

        let now = CACurrentMediaTime()
        let tolerance = 1 / displayScale
        let isAtContentTop = anchorNodeIndex == nodes.startIndex
            && anchorOffsetY <= tolerance
        let isAtContentBottom = distanceToContentBottom(
            ifWithin: tolerance * 2,
        ).map { $0 <= tolerance } ?? false
        guard force
            || isAtContentTop
            || isAtContentBottom
            || now - lastReportedPageTime >= minimumPageReportInterval
        else {
            return
        }

        reportedCurrentPageID = node.id
        lastReportedPageTime = now
        let page = node.page
        let pageID = node.id
        // 避免在 UIViewRepresentable 的更新周期内同步修改 SwiftUI Observation 状态。
        Task { @MainActor [weak self] in
            guard let self,
                  reportedCurrentPageID == pageID
            else {
                return
            }

            onCurrentPageChange?(page)
        }
    }

    /// 在低频稳定边界回报主可见页，并与普通页码上报独立去重。
    @discardableResult
    func reportStablePageIfNeeded() -> Bool {
        guard let node = mostRelevantVisibleNode(), let page = node.page.resolvedPage else {
            return false
        }
        guard lastStablePageID != node.id else {
            return true
        }

        lastStablePageID = node.id
        let pageID = node.id
        let generation = stablePageContentGeneration
        Task { @MainActor [weak self] in
            guard let self,
                  stablePageContentGeneration == generation,
                  lastStablePageID == pageID,
                  nodeIndexByID[pageID] != nil
            else {
                return
            }

            onStablePageChange?(page)
        }
        return true
    }

    /// 内容替换或程序化定位完成布局后消费一次待回报稳定页。
    func reportPendingStablePageIfNeeded() {
        guard hasPendingStablePageReport,
              reportStablePageIfNeeded()
        else {
            return
        }

        hasPendingStablePageReport = false
    }

    /// 返回当前 viewport 中最适合作为页码提示的一张页面。
    func mostRelevantVisibleNode() -> ReaderCanvasNode? {
        let visibleRange = localIndexRange(
            minY: 0,
            maxY: bounds.height,
        )

        // 程序化跳页后优先使用目标页，避免真实图片高度更新时页码滑块回弹。
        if let activeScrollAnchorPageID,
           let anchorIndex = nodeIndexByID[activeScrollAnchorPageID],
           visibleRange.contains(anchorIndex) {
            return nodes[anchorIndex]
        }

        // 第一张图较矮时面积权重可能选中第二页；内容顶部必须稳定显示第一页。
        if anchorNodeIndex == nodes.startIndex,
           anchorOffsetY <= 1 / displayScale {
            return nodes.first
        }

        // 最后一张短图无法靠近屏幕中心，滚到底部时直接以末页为准。
        if distanceToContentBottom(
            ifWithin: 2 / displayScale,
        ).map({ $0 <= 1 / displayScale }) ?? false,
            let lastIndex = visibleRange.last {
            return nodes[lastIndex]
        }

        var bestNode: ReaderCanvasNode?
        var bestTopY = CGFloat.greatestFiniteMagnitude
        var bestScore = -CGFloat.greatestFiniteMagnitude
        var pageTopY = visibleRange.isEmpty
            ? 0
            : screenTopY(for: visibleRange.lowerBound)
        for index in visibleRange {
            let node = nodes[index]
            let intersectionMinY = max(pageTopY, 0)
            let intersectionMaxY = min(
                pageTopY + node.height,
                bounds.height,
            )
            let visibleHeight = intersectionMaxY - intersectionMinY
            guard visibleHeight > 0 else {
                pageTopY += node.height
                continue
            }

            let visibleMidY = (intersectionMinY + intersectionMaxY) / 2
            let viewportMidY = bounds.height / 2
            let centerDistance = abs(visibleMidY - viewportMidY)
            let score = visibleHeight - centerDistance * 0.25
            if score > bestScore
                || (score == bestScore
                    && pageTopY < bestTopY) {
                bestScore = score
                bestTopY = pageTopY
                bestNode = node
            }
            pageTopY += node.height
        }

        return bestNode
    }
}

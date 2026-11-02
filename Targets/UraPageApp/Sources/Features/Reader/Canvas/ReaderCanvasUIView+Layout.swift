import UIKit

extension ReaderCanvasUIView {
    /// 按当前 Canvas 宽度更新所有节点自身高度，不建立整章绝对坐标。
    ///
    /// 该方法只在内容替换或 Canvas 尺寸变化时执行；单张图片返回真实比例时
    /// 只更新对应节点，不再重排它后面的全部页面。
    func layoutNodes() {
        for index in nodes.indices {
            nodes[index].height = height(for: nodes[index])
        }
        pendingAspectRatioPageIDs.removeAll()
    }

    /// 重建 ReaderPagePosition 到节点下标的查找表，并恢复锚页缓存下标。
    func rebuildNodeIndex() {
        nodeIndexByID = Dictionary(
            uniqueKeysWithValues: nodes.enumerated().map { index, node in
                (node.id, index)
            },
        )
        anchorNodeIndex = anchorPageID.flatMap { nodeIndexByID[$0] }
    }

    /// 批量提交一帧内返回的真实图片比例，只更新发生变化的节点自身高度。
    func applyPendingAspectRatioChanges() {
        let pageIDs = pendingAspectRatioPageIDs
        pendingAspectRatioPageIDs.removeAll()
        let changedIndices = pageIDs.compactMap { nodeIndexByID[$0] }
        guard !changedIndices.isEmpty else {
            return
        }

        // 向上阅读时，优先记住变化页下方最后一张稳定可见页的顶部位置。
        // 上方慢图从占位高度切换到真实高度后，使已加载的下方内容留在原位。
        // 程序化跳页仍由 activeScrollAnchorPageID 锁定目标页，不参与方向补偿。
        let upwardReference = upwardAspectRatioReference(
            changedIndices: changedIndices,
        )

        for index in changedIndices where nodes.indices.contains(index) {
            nodes[index].height = height(for: nodes[index])
        }

        if activeScrollAnchorPageID != nil {
            reapplyActiveScrollAnchorIfNeeded()
        } else if let upwardReference,
                  let referenceIndex = nodeIndexByID[upwardReference.pageID],
                  nodes.indices.contains(referenceIndex) {
            let updatedTopY = screenTopY(for: referenceIndex)
            let correction = updatedTopY - upwardReference.screenTopY
            if abs(correction) >= 1 / displayScale {
                // anchorOffsetY 增大会使局部页面整体上移，
                // 因此加上新旧坐标差即可恢复参考页原来的屏幕位置。
                anchorOffsetY += correction
            }
        }
        clampScrollAnchor()
    }

    /// 向上阅读时选择变化页下方的稳定可见页作为局部布局参考。
    private func upwardAspectRatioReference(
        changedIndices: [Int],
    ) -> (pageID: ReaderPagePosition, screenTopY: CGFloat)? {
        guard preloadDirection == .upward,
              activeScrollAnchorPageID == nil,
              let anchorIndex = anchorNodeIndex,
              nodes.indices.contains(anchorIndex),
              !(anchorIndex == nodes.startIndex
                  && anchorOffsetY <= 1 / displayScale),
              let firstChangedIndex = changedIndices.min()
        else {
            return nil
        }

        let changedIndexSet = Set(changedIndices)
        let visibleRange = localIndexRange(
            minY: 0,
            maxY: bounds.height,
        )
        guard let referenceIndex = visibleRange.reversed().first(where: {
            $0 > firstChangedIndex && !changedIndexSet.contains($0)
        }) else {
            return nil
        }

        return (
            pageID: nodes[referenceIndex].id,
            screenTopY: screenTopY(for: referenceIndex),
        )
    }

    /// 按当前 Canvas 宽度和页面真实比例计算展示高度。
    func height(for node: ReaderCanvasNode) -> CGFloat {
        let width = max(bounds.width, 1)
        let aspectRatio = node.aspectRatio ?? (4.0 / 3.0)
        return pixelAligned(width * aspectRatio)
    }

    /// 将布局坐标对齐到当前屏幕像素，避免页面之间出现细缝。
    func pixelAligned(_ value: CGFloat) -> CGFloat {
        round(value * displayScale) / displayScale
    }

    /// 从当前锚页向两侧展开，返回与指定屏幕坐标区间相交的节点范围。
    ///
    /// 计算量只与附近需要展示的页面数量有关，不读取整章其余节点的位置。
    func localIndexRange(
        minY: CGFloat,
        maxY: CGFloat,
    ) -> Range<Int> {
        guard let anchorIndex = anchorNodeIndex,
              nodes.indices.contains(anchorIndex),
              maxY >= minY
        else {
            return 0 ..< 0
        }

        var lowerBound = anchorIndex
        var lowerTopY = -anchorOffsetY
        while lowerBound > nodes.startIndex,
              lowerTopY > minY {
            lowerBound -= 1
            lowerTopY -= nodes[lowerBound].height
        }

        var upperBound = anchorIndex + 1
        var nextTopY = -anchorOffsetY + nodes[anchorIndex].height
        while upperBound < nodes.endIndex,
              nextTopY < maxY {
            nextTopY += nodes[upperBound].height
            upperBound += 1
        }

        return lowerBound ..< upperBound
    }

    /// 返回指定节点顶部相对 Canvas 视口顶部的局部坐标。
    func screenTopY(for index: Int) -> CGFloat {
        guard let anchorIndex = anchorNodeIndex,
              nodes.indices.contains(anchorIndex),
              nodes.indices.contains(index)
        else {
            return 0
        }

        var topY = -anchorOffsetY
        if index < anchorIndex {
            for nodeIndex in index ..< anchorIndex {
                topY -= nodes[nodeIndex].height
            }
        } else if index > anchorIndex {
            for nodeIndex in anchorIndex ..< index {
                topY += nodes[nodeIndex].height
            }
        }
        return topY
    }

    /// 返回内容顶部距离视口顶部的距离；超过关心范围时停止向上遍历。
    func distanceToContentTop(ifWithin limit: CGFloat) -> CGFloat? {
        guard var index = anchorNodeIndex,
              nodes.indices.contains(index)
        else {
            return nil
        }

        var distance = anchorOffsetY + topBoundaryContentHeight
        while index > nodes.startIndex,
              distance < limit {
            index -= 1
            distance += nodes[index].height
        }
        return index == nodes.startIndex && distance < limit
            ? distance
            : nil
    }

    /// 返回内容底部距离视口底部的距离；超过关心范围时停止向下遍历。
    func distanceToContentBottom(ifWithin limit: CGFloat) -> CGFloat? {
        guard var index = anchorNodeIndex,
              nodes.indices.contains(index)
        else {
            return nil
        }

        let targetHeight = bounds.height + limit
        var heightBelowViewportTop = nodes[index].height - anchorOffsetY
        index += 1
        while index < nodes.endIndex,
              heightBelowViewportTop < targetHeight {
            heightBelowViewportTop += nodes[index].height
            index += 1
        }
        if index == nodes.endIndex {
            heightBelowViewportTop += bottomBoundaryContentHeight
        }
        return index == nodes.endIndex && heightBelowViewportTop < targetHeight
            ? heightBelowViewportTop - bounds.height
            : nil
    }

    /// 清空没有内容时的滚动锚点。
    func clearScrollAnchor() {
        anchorPageID = nil
        anchorNodeIndex = nil
        anchorOffsetY = 0
    }

    /// 将视口定位到第一页顶部。
    func resetScrollAnchorToTop() {
        guard !nodes.isEmpty else {
            clearScrollAnchor()
            return
        }

        setScrollAnchor(at: nodes.startIndex, offsetY: 0)
    }

    /// 直接以指定节点及页内偏移建立滚动锚点。
    func setScrollAnchor(
        at index: Int,
        offsetY: CGFloat,
    ) {
        guard nodes.indices.contains(index) else {
            clearScrollAnchor()
            return
        }

        anchorPageID = nodes[index].id
        anchorNodeIndex = index
        anchorOffsetY = offsetY
    }

    /// 限制锚点不离开完整内容顶部和底部，并返回是否发生边界修正。
    @discardableResult
    func clampScrollAnchor() -> Bool {
        guard !nodes.isEmpty else {
            clearScrollAnchor()
            return false
        }

        normalizeScrollAnchor()
        guard let anchorIndex = anchorNodeIndex else {
            return false
        }

        if anchorIndex == nodes.startIndex,
           anchorOffsetY < -topBoundaryContentHeight {
            anchorOffsetY = -topBoundaryContentHeight
            return true
        }

        return alignScrollAnchorToContentBottomIfNeeded()
    }

    /// 当视口已经越过内容底部时，从末页反向建立恰好贴底的锚点。
    private func alignScrollAnchorToContentBottomIfNeeded() -> Bool {
        guard var index = anchorNodeIndex,
              nodes.indices.contains(index),
              bounds.height > 0
        else {
            return false
        }

        var remainingHeight = nodes[index].height - anchorOffsetY
        index += 1
        while index < nodes.endIndex,
              remainingHeight < bounds.height {
            remainingHeight += nodes[index].height
            index += 1
        }
        if index == nodes.endIndex {
            remainingHeight += bottomBoundaryContentHeight
        }
        guard index == nodes.endIndex,
              remainingHeight < bounds.height
        else {
            return false
        }

        var requiredHeight = bounds.height - bottomBoundaryContentHeight
        if requiredHeight <= 0 {
            setScrollAnchor(
                at: nodes.index(before: nodes.endIndex),
                offsetY: nodes.last?.height ?? 0,
            )
            return true
        }
        var bottomIndex = nodes.index(before: nodes.endIndex)
        while bottomIndex > nodes.startIndex,
              requiredHeight > nodes[bottomIndex].height {
            requiredHeight -= nodes[bottomIndex].height
            bottomIndex -= 1
        }

        if bottomIndex == nodes.startIndex,
           requiredHeight > nodes[bottomIndex].height + topBoundaryContentHeight {
            setScrollAnchor(
                at: nodes.startIndex,
                offsetY: -topBoundaryContentHeight,
            )
        } else {
            setScrollAnchor(
                at: bottomIndex,
                offsetY: nodes[bottomIndex].height - requiredHeight,
            )
        }
        return true
    }

    /// 计算两个锚点位置之间的有符号距离；只在内容边界修正时使用。
    func scrollDistance(
        from startIndex: Int,
        offsetY startOffsetY: CGFloat,
        to endIndex: Int,
        offsetY endOffsetY: CGFloat,
    ) -> CGFloat {
        guard nodes.indices.contains(startIndex),
              nodes.indices.contains(endIndex)
        else {
            return 0
        }

        if startIndex == endIndex {
            return endOffsetY - startOffsetY
        }
        if endIndex > startIndex {
            var distance = nodes[startIndex].height - startOffsetY
            if endIndex > startIndex + 1 {
                for index in (startIndex + 1) ..< endIndex {
                    distance += nodes[index].height
                }
            }
            return distance + endOffsetY
        }

        var distance = startOffsetY
        if startIndex > endIndex + 1 {
            for index in (endIndex + 1) ..< startIndex {
                distance += nodes[index].height
            }
        }
        distance += nodes[endIndex].height - endOffsetY
        return -distance
    }
}

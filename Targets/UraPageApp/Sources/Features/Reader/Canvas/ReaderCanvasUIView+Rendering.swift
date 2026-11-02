import UIKit

extension ReaderCanvasUIView {
    /// 按当前滚动方向更新 View 窗口和独立的图片预加载窗口。
    func updatePageWindow(force: Bool = false) {
        guard bounds.width > 0,
              bounds.height > 0
        else {
            return
        }

        if !pendingAspectRatioPageIDs.isEmpty {
            applyPendingAspectRatioChanges()
        }

        let topPreloadScreenCount = preloadDirection == .upward
            ? primaryPreloadScreenCount
            : secondaryPreloadScreenCount
        let bottomPreloadScreenCount = preloadDirection == .downward
            ? primaryPreloadScreenCount
            : secondaryPreloadScreenCount
        let renderedRange = localIndexRange(
            minY: -bounds.height * topPreloadScreenCount,
            maxY: bounds.height
                + bounds.height * bottomPreloadScreenCount,
        )
        let visibleRange = localIndexRange(
            minY: 0,
            maxY: bounds.height,
        )
        let imagePreloadRange = makeImagePreloadRange(
            renderedRange: renderedRange,
            visibleRange: visibleRange,
        )
        // 清单只按下方 2 屏、上方 1 屏取批次；图片至少 8 页的规则不扩大清单预取。
        let nextManifestRange = localIndexRange(minY: -bounds.height, maxY: bounds.height * 3)
        let didChangeManifestRange = manifestPreloadRange != nextManifestRange
        manifestPreloadRange = nextManifestRange
        let didChangeVisibleRange = lastVisibleRange != visibleRange
        let didChangeImagePreloadWindow = lastImagePreloadRange != imagePreloadRange || didChangeManifestRange
        if didChangeVisibleRange || didChangeImagePreloadWindow {
            // 可见范围变化不一定会改变图片窗口，因此确保当前可见页已经开始加载。
            for index in visibleRange {
                loadPageIfNeeded(nodes[index].id, priority: .visible)
            }
            lastVisibleRange = visibleRange
        }

        if didChangeImagePreloadWindow {
            let newWindowIDs = Set(imagePreloadRange.map { nodes[$0].id })
            // 节点只保留当前窗口的位图（动画图由节点强持有）；离屏页面仍保留比例，
            // 回看时静态图命中限额缓存、动画图经磁盘优先入口重建。
            for id in activeImageWindowPageIDs where !newWindowIDs.contains(id) {
                guard let index = nodeIndexByID[id] else { continue }

                nodes[index].image = nil
                nodes[index].imageDisplayMode = nil
                nodes[index].retainedAnimatedImage = nil
            }
            activeImageWindowPageIDs = newWindowIDs
            lastImagePreloadRange = imagePreloadRange

            // 只在图片窗口跨过页面边界时重新安排预加载。
            loadPrefetchedPages(
                in: imagePreloadRange,
                visibleRange: visibleRange,
            )
        }

        let canOnlyUpdateFrames = !force
            && !didChangeImagePreloadWindow
            && lastRenderedBounds == bounds
            && lastRenderedRange == renderedRange
        if canOnlyUpdateFrames {
            // 固定视口滚动时，每帧只移动窗口内既有 View；不重新配置内容、
            // 创建 identity 集合或安排图片任务，避免把这些工作放进滚动热路径。
            updateRenderedPageFrames(in: renderedRange, visibleRange: visibleRange)
            updateChapterBoundaryFrames(renderedRange: renderedRange)
            reportCurrentPageIfNeeded()
            triggerTopBoundaryLoadIfNeeded()
            triggerBottomBoundaryLoadIfNeeded()
            return
        }

        let renderedIDs = Set(renderedRange.map { nodes[$0].id })
        // 先回收已经离开窗口的 View，让同一次窗口更新中新进入的页面
        // 可以直接复用它们，避免复用池暂时为空时创建额外 View。
        let staleIDs = visibleViews.keys.filter {
            !renderedIDs.contains($0)
        }
        for id in staleIDs {
            guard let pageView = visibleViews.removeValue(forKey: id) else {
                continue
            }

            pageView.removeFromSuperview()
            pageView.prepareForReuse()
            reusableViews.append(pageView)
        }

        var pageTopY = renderedRange.isEmpty
            ? 0
            : screenTopY(for: renderedRange.lowerBound)
        for index in renderedRange {
            let node = nodes[index]
            let pageView = visibleViews[node.id] ?? dequeuePageView()
            pageView.frame = CGRect(
                x: 0,
                y: pixelAligned(pageTopY),
                width: bounds.width,
                height: node.height,
            )
            pageView.configure(
                page: node.page,
                image: node.image,
                failure: node.failure,
                isRetryable: canRetryFailedPage,
                onRetry: { [weak self] in
                    self?.retryPage(node.id)
                },
            )
            pageView.setVisibleInViewport(visibleRange.contains(index))
            visibleViews[node.id] = pageView
            pageTopY += node.height
        }
        updateChapterBoundaryFrames(renderedRange: renderedRange)

        // 复用池不超过当前预加载窗口的节点数量，避免离开窗口的 View 持续累积。
        while reusableViews.count > renderedIDs.count {
            reusableViews.removeLast()
        }

        lastRenderedBounds = bounds
        lastRenderedRange = renderedRange
        reportCurrentPageIfNeeded()
        triggerTopBoundaryLoadIfNeeded()
        triggerBottomBoundaryLoadIfNeeded()
    }

    /// 只更新当前窗口中页面的屏幕位置，供拖拽和惯性滚动的每一帧调用。
    private func updateRenderedPageFrames(in range: Range<Int>, visibleRange: Range<Int>) {
        var pageTopY = range.isEmpty
            ? 0
            : screenTopY(for: range.lowerBound)
        for index in range {
            let node = nodes[index]
            guard let pageView = visibleViews[node.id] else {
                pageTopY += node.height
                continue
            }

            let nextY = pixelAligned(pageTopY)
            if pageView.frame.origin.y != nextY {
                pageView.frame.origin.y = nextY
            }
            pageView.setVisibleInViewport(visibleRange.contains(index))
            pageTopY += node.height
        }
    }

    /// 在屏幕距离窗口之外，保证滚动方向前方至少有固定数量的页面提前加载。
    private func makeImagePreloadRange(
        renderedRange: Range<Int>,
        visibleRange: Range<Int>,
    ) -> Range<Int> {
        switch preloadDirection {
        case .downward:
            let minimumUpperBound = min(
                visibleRange.upperBound + minimumForwardPreloadPageCount,
                nodes.endIndex,
            )
            return renderedRange.lowerBound ..< max(
                renderedRange.upperBound,
                minimumUpperBound,
            )

        case .upward:
            let maximumLowerBound = max(
                visibleRange.lowerBound - minimumForwardPreloadPageCount,
                nodes.startIndex,
            )
            return min(
                renderedRange.lowerBound,
                maximumLowerBound,
            ) ..< renderedRange.upperBound
        }
    }

    /// 可见页之后先加载滚动方向前方，再从近到远补齐反方向窗口。
    private func loadPrefetchedPages(
        in preloadRange: Range<Int>,
        visibleRange: Range<Int>,
    ) {
        let aboveRange = preloadRange.lowerBound ..< visibleRange.lowerBound
        let belowRange = visibleRange.upperBound ..< preloadRange.upperBound

        switch preloadDirection {
        case .downward:
            for index in belowRange {
                loadPageIfNeeded(nodes[index].id, priority: .preload)
            }
            for index in aboveRange.reversed() {
                loadPageIfNeeded(nodes[index].id, priority: .preload)
            }

        case .upward:
            for index in aboveRange.reversed() {
                loadPageIfNeeded(nodes[index].id, priority: .preload)
            }
            for index in belowRange {
                loadPageIfNeeded(nodes[index].id, priority: .preload)
            }
        }
    }

    /// 接近当前最早章节顶部时只触发一次；离开顶部区域后允许失败重试。
    private func triggerTopBoundaryLoadIfNeeded() {
        guard onReachTop != nil else {
            return
        }
        guard distanceToContentTop(ifWithin: bounds.height) != nil else {
            lastTopTriggerFirstID = nil
            return
        }
        guard let firstID = nodes.first?.id,
              firstID != lastTopTriggerFirstID
        else {
            return
        }

        lastTopTriggerFirstID = firstID
        // Canvas 只通知进入边界；来源 ViewModel 确认存在上一章后再记录真实加载日志。
        Task { @MainActor [weak self] in
            self?.onReachTop?()
        }
    }

    /// 接近当前最晚章节底部时只触发一次；追加页面后允许继续触发下一章。
    private func triggerBottomBoundaryLoadIfNeeded() {
        guard onReachBottom != nil else {
            return
        }
        guard distanceToContentBottom(ifWithin: bounds.height * nextChapterPreloadScreenCount) != nil else {
            lastBottomTriggerLastID = nil
            return
        }
        guard let lastID = nodes.last?.id,
              lastID != lastBottomTriggerLastID
        else {
            return
        }

        lastBottomTriggerLastID = lastID
        // Canvas 只通知进入边界；来源 ViewModel 确认存在下一章后再记录真实加载日志。
        Task { @MainActor [weak self] in
            self?.onReachBottom?()
        }
    }

    /// 优先取出已离开预加载窗口的页面 View，否则创建新节点。
    private func dequeuePageView() -> ReaderCanvasPageView {
        let pageView = reusableViews.popLast() ?? ReaderCanvasPageView()
        addSubview(pageView)
        return pageView
    }
}

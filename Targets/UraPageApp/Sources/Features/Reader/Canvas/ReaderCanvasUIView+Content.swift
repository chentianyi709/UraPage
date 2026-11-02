import UIKit

extension ReaderCanvasUIView {
    /// 根据当前 Canvas 物理像素宽度更新静态图显示模式。
    ///
    /// 阅读图固定按屏幕物理像素生成（高分辨率图片优化，一直开启，不再提供设置）；
    /// 尺寸变化只使旧图片任务失效并重读当前窗口；页面列表、已知宽高比和滚动锚点都保持不变。
    func updateImageDisplayModeIfNeeded() {
        guard bounds.width > 0 else {
            return
        }

        let nextMode = ReaderPageImageDisplayMode(
            maximumPixelWidth: max(
                Int(ceil(bounds.width * displayScale)),
                1,
            ),
        )
        guard imageDisplayMode != nextMode else {
            return
        }

        let previousMode = imageDisplayMode
        imageDisplayMode = nextMode
        guard let previousMode else {
            return
        }

        contentGeneration += 1
        retirePageTasks(releasing: previousMode)
        foregroundRecoveryRetryPageIDs.removeAll()
        // 强制当前图片窗口按新模式重新排队。节点暂时保留旧位图，
        // 新位图逐页准备完成后再替换，避免切换设置时闪回占位图。
        lastVisibleRange = nil
        lastImagePreloadRange = nil
        resetRenderSignature()
        needsRender = true
        AppLogger.debug(
            "Reader 图片显示模式已更新，mode=\(nextMode.logDescription)，generation=\(contentGeneration)",
            category: "Reader.Cache",
        )
    }

    /// 确定性销毁 Canvas 当前内容、回调和所有异步工作。
    @discardableResult
    func stopAndCancelAllWork() -> [Task<Void, Never>] {
        isStopped = true
        AppLogger.debug(
            "Reader 停止，nodes=\(nodes.count)，views=\(visibleViews.count)，reusableViews=\(reusableViews.count)，pageTasks=\(pageTasks.count)",
            category: "Reader.Canvas",
        )
        // 先移除任务登记，使旧 taskID 无法提交，再取消并等待工作退出。
        contentGeneration += 1
        stopDisplayLink()
        isDragging = false
        let cancelledPageTasks = pageTasks.values.map(\.task) + taskRetirement.drain()
        pageTasks.removeAll()
        cancelledPageTasks.forEach { $0.cancel() }
        activeImageWindowPageIDs.removeAll()
        failedPageIDs.removeAll()
        foregroundRecoveryRetryPageIDs.removeAll()
        lastImagePreloadRange = nil
        pendingAspectRatioPageIDs.removeAll()

        pendingScrollRequest = nil
        handledScrollRequestID = nil
        activeScrollAnchorPageID = nil
        reportedCurrentPageID = nil
        lastStablePageID = nil
        stablePageContentGeneration += 1
        hasPendingStablePageReport = false
        isUserScrollSequenceActive = false
        lastTopTriggerFirstID = nil
        lastBottomTriggerLastID = nil

        pageAccess = nil
        onReachTop = nil
        onReachBottom = nil
        onRetryTopBoundary = nil
        onRetryBottomBoundary = nil
        onCurrentPageChange = nil
        onStablePageChange = nil
        onScrollRequestHandled = nil
        onTap = nil
        onScrollStart = nil
        topBoundaryPresentation = nil
        bottomBoundaryPresentation = nil
        topBoundaryView.configure(presentation: nil, onRetry: nil)
        bottomBoundaryView.configure(presentation: nil, onRetry: nil)

        for view in visibleViews.values {
            view.removeFromSuperview()
            view.prepareForReuse()
        }
        visibleViews.removeAll()
        reusableViews.removeAll()
        nodes.removeAll()
        pageIDs.removeAll()
        nodeIndexByID.removeAll()
        configuredContentVersion = nil
        manifestPreloadRange = nil
        clearScrollAnchor()
        resetRenderSignature()
        return cancelledPageTasks
    }

    /// 替换展示节点但保留进行中的页面任务；结果按页面身份提交，不覆盖其它章节。
    func replacePages(_ pages: [ReaderPageSlot]) {
        contentGeneration += 1
        activeImageWindowPageIDs.removeAll()
        failedPageIDs.removeAll()
        foregroundRecoveryRetryPageIDs.removeAll()
        lastImagePreloadRange = nil
        lastTopTriggerFirstID = nil
        lastBottomTriggerLastID = nil
        reportedCurrentPageID = nil
        lastReportedPageTime = 0
        lastStablePageID = nil
        stablePageContentGeneration += 1
        hasPendingStablePageReport = !pages.isEmpty
        isUserScrollSequenceActive = false
        activeScrollAnchorPageID = nil
        for view in visibleViews.values {
            view.removeFromSuperview()
            view.prepareForReuse()
        }
        visibleViews.removeAll()
        reusableViews.removeAll()

        nodes = pages.map { ReaderCanvasNode(page: $0) }
        pageIDs = pages.map(\.identity)
        rebuildNodeIndex()
        // 完整替换内容时重新计算所有节点高度，并清空上一代尚未合并的图片比例。
        // 章节增量扩展则只在创建新节点时计算占位高度。
        layoutNodes()
        resetScrollAnchorToTop()
        decelerationVelocityY = 0
        preloadDirection = .downward
        preloadDirectionChangeDistanceY = 0
        resetRenderSignature()
        needsRender = true
        AppLogger.debug(
            "Reader 内容已替换，generation=\(contentGeneration)，pages=\(pages.count)",
            category: "Reader.Canvas",
        )
    }

    /// 从 Canvas 已有页面定位真实增量，允许 SwiftUI 合并多次前后章加载。
    /// 同一 replacementVersion 内旧页面保持连续，只在两端增加页面；
    /// 复用节点、图片任务和锚点，不依赖 ViewModel 上一次提交时的页数。
    func expandPagesPreservingOffset(_ pages: [ReaderPageSlot]) {
        guard let firstPageID = pageIDs.first,
              let existingStartIndex = pages.firstIndex(where: { $0.identity == firstPageID })
        else {
            replacePages(pages)
            return
        }

        let appendedStartIndex = existingStartIndex + nodes.count
        if appendedStartIndex < pages.endIndex {
            appendPagesPreservingOffset(Array(pages[appendedStartIndex...]))
        }
        if existingStartIndex > pages.startIndex {
            prependPagesPreservingOffset(Array(pages[..<existingStartIndex]))
        }
    }

    /// 只追加新页面和对应下标，避免向下连续阅读时
    /// 每加载一章都扫描并重建全部旧节点。
    private func appendPagesPreservingOffset(_ appendedPages: [ReaderPageSlot]) {
        let previousPageCount = nodes.count
        let nextPageCount = previousPageCount + appendedPages.count
        nodes.reserveCapacity(nextPageCount)
        pageIDs.reserveCapacity(nextPageCount)
        nodeIndexByID.reserveCapacity(nextPageCount)

        for page in appendedPages {
            var node = ReaderCanvasNode(page: page)
            node.height = height(for: node)
            nodes.append(node)
            pageIDs.append(page.identity)
            nodeIndexByID[page.identity] = nodes.index(before: nodes.endIndex)
        }

        lastImagePreloadRange = nil
        reapplyActiveScrollAnchorIfNeeded()
        clampScrollAnchor()
        resetRenderSignature()
        needsRender = true
        AppLogger.debug(
            "Reader 内容已向下追加，pages=\(nodes.count)，appended=\(appendedPages.count)，anchorIndex=\(anchorNodeIndex ?? -1)，anchorOffsetY=\(Int(anchorOffsetY))",
            category: "Reader.Canvas",
        )
    }

    /// 复用旧节点向顶部增量插入相邻章节。
    ///
    /// 上方追加页面后只更新锚页的缓存下标；锚页身份和页内偏移保持不变，
    /// 因此无需累计新增页面高度或人工修正当前位置。
    private func prependPagesPreservingOffset(_ prependedPages: [ReaderPageSlot]) {
        let prependedNodes = prependedPages.map { page -> ReaderCanvasNode in
            var node = ReaderCanvasNode(page: page)
            node.height = height(for: node)
            return node
        }

        // 复用旧节点：只在数组头部就地插入，不再构造并整体替换一个更大的节点数组。
        // 这与 append 的写法对称，避免上扩时同时存在两份节点（峰值内存翻倍）。
        let prependedCount = prependedNodes.count
        nodes.insert(contentsOf: prependedNodes, at: 0)
        pageIDs.insert(contentsOf: prependedPages.map(\.identity), at: 0)
        // 已有节点下标整体后移固定数量：一次 mapValues 平移旧下标，再登记新增节点的下标，
        // 不必按 identity 逐页重建整张查找表。
        nodeIndexByID = nodeIndexByID.mapValues { $0 + prependedCount }
        for (offset, node) in prependedNodes.enumerated() {
            nodeIndexByID[node.id] = offset
        }
        anchorNodeIndex = anchorPageID.flatMap { nodeIndexByID[$0] }
        lastImagePreloadRange = nil
        reapplyActiveScrollAnchorIfNeeded()
        clampScrollAnchor()
        resetRenderSignature()
        needsRender = true
        AppLogger.debug(
            "Reader 内容已向上扩展，pages=\(nodes.count)，prepended=\(prependedPages.count)，anchorIndex=\(anchorNodeIndex ?? -1)，anchorOffsetY=\(Int(anchorOffsetY))",
            category: "Reader.Canvas",
        )
    }

    /// 让下一次渲染重新计算视口节点。
    func resetRenderSignature() {
        lastRenderedBounds = nil
        lastRenderedRange = nil
    }

    /// 取消后仍等待实际退出；画质变体必须在旧任务停止写入后才能释放。
    func retirePageTasks(releasing displayMode: ReaderPageImageDisplayMode? = nil) {
        let tasks = pageTasks.values.map(\.task)
        pageTasks.removeAll()
        let identities = activeImageWindowPageIDs.compactMap { id in
            nodeIndexByID[id].flatMap { nodes[$0].page.resolvedPage?.identity }
        }
        let pageAccess = pageAccess
        let loader = pageImageLoader
        taskRetirement.cancel(tasks) {
            if let displayMode, let pageAccess {
                await loader.releaseMemoryImages(
                    for: identities,
                    displayMode: displayMode,
                    pageAccess: pageAccess,
                )
            }
        }
    }
}

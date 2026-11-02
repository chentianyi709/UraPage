import UIKit

extension ReaderCanvasUIView {
    /// 安装纵向滚动与阅读控制显隐使用的全屏手势。
    func setupGestures() {
        let gesture = UIPanGestureRecognizer(
            target: self,
            action: #selector(handlePan(_:)),
        )
        gesture.delegate = self
        addGestureRecognizer(gesture)

        let tapGesture = UITapGestureRecognizer(
            target: self,
            action: #selector(handleTap),
        )
        tapGesture.numberOfTapsRequired = ReaderChromeToggleMode.doubleTap.tapCount
        tapGesture.delegate = self
        tapGesture.cancelsTouchesInView = false
        addGestureRecognizer(tapGesture)
        chromeTapGesture = tapGesture
    }

    /// 按当前设置把页面点击交给来源 Reader 切换控制栏显示状态。
    @objc private func handleTap() {
        onTap?()
    }

    /// 把手指拖拽转换为虚拟内容偏移，离手后转入 display link 惯性。
    @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
        switch gesture.state {
        case .began:
            // 用户开始手动滚动后，程序化跳页目标不再限制当前页判定。
            activeScrollAnchorPageID = nil
            // 即使最终仍停在同一页，也要重新确认一次本轮滚动后的稳定位置。
            lastStablePageID = nil
            stopDisplayLink()
            isDragging = true
            isUserScrollSequenceActive = true
            decelerationVelocityY = 0
            onScrollStart?()
            startDisplayLinkIfNeeded()

        case .changed:
            let translation = gesture.translation(in: self)
            gesture.setTranslation(.zero, in: self)
            let actualDistanceY = moveScrollAnchor(by: -translation.y)
            recordPreloadDirectionMovement(actualDistanceY)
            needsRender = true
            startDisplayLinkIfNeeded()

        case .ended:
            isDragging = false
            decelerationVelocityY = -gesture.velocity(in: self).y
            // 低速松手也保留一小段惯性，只过滤已经接近静止的速度。
            if abs(decelerationVelocityY) < minimumDecelerationVelocity {
                decelerationVelocityY = 0
                needsRender = true
            }
            startDisplayLinkIfNeeded()

        case .cancelled, .failed:
            // 系统中断的手势没有有效的“松手速度”，不应该继续惯性滚动。
            isDragging = false
            decelerationVelocityY = 0
            needsRender = true

        default:
            break
        }
    }

    /// 累计与当前方向相反的实际位移，达到四分之一屏高后才确认方向切换。
    private func recordPreloadDirectionMovement(_ distanceY: CGFloat) {
        guard bounds.height > 0,
              distanceY != 0
        else {
            return
        }

        switch preloadDirection {
        case .downward:
            preloadDirectionChangeDistanceY = min(
                preloadDirectionChangeDistanceY + distanceY,
                0,
            )

        case .upward:
            preloadDirectionChangeDistanceY = max(
                preloadDirectionChangeDistanceY + distanceY,
                0,
            )
        }

        let threshold = bounds.height * preloadDirectionChangeScreenRatio
        guard abs(preloadDirectionChangeDistanceY) >= threshold else {
            return
        }

        preloadDirection = preloadDirection == .downward
            ? .upward
            : .downward
        preloadDirectionChangeDistanceY = 0
        lastImagePreloadRange = nil
        resetRenderSignature()
        needsRender = true
    }

    /// 在滚动、布局合并或页面状态变化时启动屏幕同步驱动。
    func startDisplayLinkIfNeeded() {
        guard displayLink == nil else {
            return
        }

        lastDisplayTimestamp = 0
        let proxy = displayLinkProxy ?? ReaderCanvasDisplayLinkProxy()
        proxy.target = self
        displayLinkProxy = proxy

        let link = CADisplayLink(
            target: proxy,
            selector: #selector(ReaderCanvasDisplayLinkProxy.tick(_:)),
        )
        link.preferredFrameRateRange = CAFrameRateRange(
            minimum: 60,
            maximum: 120,
            preferred: 120,
        )
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    /// 停止屏幕驱动，并清空惯性速度。
    func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
        lastDisplayTimestamp = 0
        decelerationVelocityY = 0
    }

    /// 每帧推进虚拟惯性并统一提交视口。
    @objc func handleDisplayLink(_ link: CADisplayLink) {
        if lastDisplayTimestamp == 0 {
            lastDisplayTimestamp = link.timestamp
        } else if !isDragging,
                  decelerationVelocityY != 0 {
            let deltaTime = link.timestamp - lastDisplayTimestamp
            lastDisplayTimestamp = link.timestamp

            if deltaTime > maximumContinuousFrameInterval {
                // App 挂起或主线程长时间停顿后不补算大段位移，避免恢复时突然跳页。
                decelerationVelocityY = 0
            } else {
                advanceDeceleration(by: deltaTime)
            }
            needsRender = true
        } else {
            lastDisplayTimestamp = link.timestamp
        }

        if needsRender {
            updatePageWindow()
            needsRender = false
        }

        if !isDragging,
           decelerationVelocityY == 0,
           !needsRender {
            // 节流期间被暂缓的页码必须在滚动停止时提交，避免停留在旧页。
            reportCurrentPageIfNeeded(force: true)
            if isUserScrollSequenceActive {
                reportStablePageIfNeeded()
                isUserScrollSequenceActive = false
            }
            stopDisplayLink()
        }
    }

    /// 使用系统普通减速率的解析解推进一次惯性，避免滚动距离依赖刷新帧数。
    private func advanceDeceleration(by deltaTime: CFTimeInterval) {
        let exponent = decelerationLogRatePerSecond * deltaTime
        let decayDelta = expm1(exponent)
        let decay = decayDelta + 1
        let travelTime = decayDelta / decelerationLogRatePerSecond
        let requestedDistanceY = decelerationVelocityY * CGFloat(travelTime)
        let actualDistanceY = moveScrollAnchor(by: requestedDistanceY)
        recordPreloadDirectionMovement(actualDistanceY)

        guard abs(actualDistanceY - requestedDistanceY) < 1 / displayScale else {
            decelerationVelocityY = 0
            return
        }

        decelerationVelocityY *= CGFloat(decay)
        if abs(decelerationVelocityY) < minimumDecelerationVelocity {
            decelerationVelocityY = 0
        }
    }

    /// 推进锚页内偏移，并在跨过页面边界时把锚点归一到相邻页面。
    ///
    /// 返回经过内容边界限制后的实际位移，供方向判断和惯性终止使用。
    @discardableResult
    func moveScrollAnchor(by distanceY: CGFloat) -> CGFloat {
        guard !nodes.isEmpty else {
            clearScrollAnchor()
            return 0
        }

        if anchorNodeIndex == nil {
            resetScrollAnchorToTop()
        }

        let previousIndex = anchorNodeIndex ?? nodes.startIndex
        let previousOffsetY = anchorOffsetY
        anchorOffsetY += distanceY
        let didClamp = clampScrollAnchor()
        guard didClamp,
              let currentIndex = anchorNodeIndex
        else {
            return distanceY
        }

        return scrollDistance(
            from: previousIndex,
            offsetY: previousOffsetY,
            to: currentIndex,
            offsetY: anchorOffsetY,
        )
    }

    /// 把超出当前锚页的局部偏移移动到相邻节点，不进行全局坐标查找。
    func normalizeScrollAnchor() {
        guard var index = anchorNodeIndex,
              nodes.indices.contains(index)
        else {
            resetScrollAnchorToTop()
            return
        }

        while anchorOffsetY < 0, index > nodes.startIndex {
            index -= 1
            anchorOffsetY += nodes[index].height
        }
        while anchorOffsetY >= nodes[index].height,
              index < nodes.index(before: nodes.endIndex) {
            anchorOffsetY -= nodes[index].height
            index += 1
        }

        anchorNodeIndex = index
        anchorPageID = nodes[index].id
    }

    /// 在目标页面已经存在且 Canvas 获得尺寸后执行一次顶部对齐跳转。
    @discardableResult
    func applyPendingScrollRequestIfNeeded() -> Bool {
        guard bounds.width > 0,
              bounds.height > 0,
              let request = pendingScrollRequest,
              request.id != handledScrollRequestID,
              let index = nodeIndexByID[request.pageID],
              nodes.indices.contains(index)
        else {
            return false
        }

        stopDisplayLink()
        // 旧位置的任务继续完成并缓存；新位置立即规划自己的请求，不等待旧窗口。
        lastImagePreloadRange = nil
        manifestPreloadRange = nil
        isUserScrollSequenceActive = false
        let previousIndex = anchorNodeIndex ?? index
        let previousOffsetY = anchorOffsetY
        activeScrollAnchorPageID = request.pageID
        setScrollAnchor(at: index, offsetY: 0)
        clampScrollAnchor()
        let currentIndex = anchorNodeIndex ?? index
        let isMovingUpward = currentIndex < previousIndex
            || (currentIndex == previousIndex
                && anchorOffsetY < previousOffsetY)
        preloadDirection = isMovingUpward ? .upward : .downward
        preloadDirectionChangeDistanceY = 0
        reportedCurrentPageID = nil
        lastReportedPageTime = 0
        lastStablePageID = nil
        handledScrollRequestID = request.id
        pendingScrollRequest = nil
        hasPendingStablePageReport = true
        let requestID = request.id
        // 与页码回报分开确认命令，避免旧页面回调提前清除尚未执行的跳页请求。
        Task { @MainActor [weak self] in
            guard let self,
                  handledScrollRequestID == requestID
            else {
                return
            }

            activeScrollAnchorPageID = nil
            onScrollRequestHandled?(requestID)
        }
        resetRenderSignature()
        needsRender = true
        AppLogger.debug(
            "Reader 跳转页面，chapterID=\(request.pageID.chapter.chapterID)，pageID=\(request.pageID.index + 1)，anchorIndex=\(anchorNodeIndex ?? -1)，anchorOffsetY=\(Int(anchorOffsetY))",
            category: "Reader.Scroll",
        )
        return true
    }

    /// 图片高度或 Canvas 尺寸变化时继续把程序化跳页目标固定在原位置。
    func reapplyActiveScrollAnchorIfNeeded() {
        guard let activeScrollAnchorPageID,
              let index = nodeIndexByID[activeScrollAnchorPageID],
              nodes.indices.contains(index)
        else {
            return
        }

        setScrollAnchor(at: index, offsetY: 0)
    }
}

extension ReaderCanvasUIView: UIGestureRecognizerDelegate {
    /// 横向手势留给外层 NavigationStack 的系统返回交互。
    override func gestureRecognizerShouldBegin(
        _ gestureRecognizer: UIGestureRecognizer,
    ) -> Bool {
        guard let panGesture = gestureRecognizer as? UIPanGestureRecognizer else {
            return true
        }

        let velocity = panGesture.velocity(in: self)
        return abs(velocity.y) >= abs(velocity.x)
    }

    /// 点击单页失败按钮时不同时触发阅读控制栏显隐。
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldReceive touch: UITouch,
    ) -> Bool {
        guard gestureRecognizer is UITapGestureRecognizer else {
            return true
        }

        var touchedView = touch.view
        while let view = touchedView {
            if view is UIControl {
                return false
            }
            touchedView = view.superview
        }
        return true
    }
}

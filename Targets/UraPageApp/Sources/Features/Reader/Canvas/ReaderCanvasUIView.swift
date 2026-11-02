import SwiftUI
import UIKit

/// 描述 Canvas 当前优先预加载图片的滚动方向。
enum ReaderCanvasPreloadDirection {
    case upward
    case downward
}

/// 把单页任务和它的提交序号作为一个状态保存，
/// 避免两张字典分别更新后出现不一致。
struct ReaderCanvasPageTask {
    let id: Int
    let task: Task<Void, Never>
}

/// 使用固定视口、页面锚点和少量复用节点显示连续漫画页。
final class ReaderCanvasUIView: UIView {
    var nodes: [ReaderCanvasNode] = []
    var pageIDs: [ReaderPagePosition] = []
    var nodeIndexByID: [ReaderPagePosition: Int] = [:]
    var visibleViews: [ReaderPagePosition: ReaderCanvasPageView] = [:]
    var reusableViews: [ReaderCanvasPageView] = []
    var pageTasks: [ReaderPagePosition: ReaderCanvasPageTask] = [:]
    /// 画质切换后仍在退出的任务归关闭屏障所有；切章任务保留在 pageTasks 中。
    let taskRetirement = ReaderTaskRetirement()
    var nextPageTaskID = 0

    var pageAccess: ReaderPageAccess?
    /// 失败页是否可以重试；离线只读本地资产，失败无法恢复，因此不提供重试。
    var canRetryFailedPage: Bool {
        pageAccess?.canRetryPageLoad == true
    }

    var onReachTop: (() -> Void)?
    var onReachBottom: (() -> Void)?
    var onRetryTopBoundary: (() -> Void)?
    var onRetryBottomBoundary: (() -> Void)?
    var onCurrentPageChange: ((ReaderPageSlot) -> Void)?
    var onStablePageChange: ((ComicPage) -> Void)?
    var onScrollRequestHandled: ((Int) -> Void)?
    var onTap: (() -> Void)?
    var onScrollStart: (() -> Void)?
    var chromeTapGesture: UITapGestureRecognizer?
    let pageImageLoader: ReaderPageImageLoader
    var contentGeneration = 0
    var isStopped = false
    var configuredContentVersion: Int?
    var imageDisplayMode: ReaderPageImageDisplayMode?
    var topBoundaryPresentation: ReaderCanvasChapterBoundaryPresentation?
    var bottomBoundaryPresentation: ReaderCanvasChapterBoundaryPresentation?
    let topBoundaryView = ReaderCanvasChapterBoundaryView(edge: .top)
    let bottomBoundaryView = ReaderCanvasChapterBoundaryView(edge: .bottom)

    var anchorPageID: ReaderPagePosition?
    var anchorNodeIndex: Int?
    var anchorOffsetY: CGFloat = 0
    var decelerationVelocityY: CGFloat = 0
    var isDragging = false
    var preloadDirection = ReaderCanvasPreloadDirection.downward
    var preloadDirectionChangeDistanceY: CGFloat = 0

    var displayLink: CADisplayLink?
    var displayLinkProxy: ReaderCanvasDisplayLinkProxy?
    var lastDisplayTimestamp: CFTimeInterval = 0
    var lastLayoutBounds: CGRect = .zero
    var needsRender = false
    var pendingAspectRatioPageIDs = Set<ReaderPagePosition>()

    var lastRenderedBounds: CGRect?
    var lastRenderedRange: Range<Int>?
    var lastVisibleRange: Range<Int>?
    var lastImagePreloadRange: Range<Int>?
    var manifestPreloadRange: Range<Int>?
    var activeImageWindowPageIDs = Set<ReaderPagePosition>()
    /// 保存已失败页面，让前台恢复无需扫描全部节点。
    var failedPageIDs = Set<ReaderPagePosition>()
    /// App 恢复时仍在执行、且失败后可以自动重试一次的页面。
    var foregroundRecoveryRetryPageIDs = Set<ReaderPagePosition>()
    var lastTopTriggerFirstID: ReaderPagePosition?
    var lastBottomTriggerLastID: ReaderPagePosition?
    var reportedCurrentPageID: ReaderPagePosition?
    var lastReportedPageTime: CFTimeInterval = 0
    var lastStablePageID: ReaderPagePosition?
    var stablePageContentGeneration = 0
    var hasPendingStablePageReport = false
    var isUserScrollSequenceActive = false
    var pendingScrollRequest: ReaderCanvasScrollRequest?
    var handledScrollRequestID: Int?
    var activeScrollAnchorPageID: ReaderPagePosition?

    let decelerationLogRatePerSecond = log(
        Double(UIScrollView.DecelerationRate.normal.rawValue),
    ) * 1000
    let minimumDecelerationVelocity: CGFloat = 5
    let maximumContinuousFrameInterval: CFTimeInterval = 0.25
    let primaryPreloadScreenCount: CGFloat = 2
    let secondaryPreloadScreenCount: CGFloat = 1
    let minimumForwardPreloadPageCount = 8
    let nextChapterPreloadScreenCount: CGFloat = 2
    let preloadDirectionChangeScreenRatio: CGFloat = 0.25
    let minimumPageReportInterval: CFTimeInterval = 0.15
    let chapterBoundaryHeight: CGFloat = 150

    var displayScale: CGFloat {
        max(traitCollection.displayScale, 1)
    }

    /// 使用当前 Reader 专用缓存的加载器创建 Canvas。
    init(pageImageLoader: ReaderPageImageLoader) {
        self.pageImageLoader = pageImageLoader
        super.init(frame: .zero)
        // 资产目录中的动态颜色先由 SwiftUI Color 解析，再桥接给 UIKit。
        backgroundColor = UIColor(.readerBackground)
        clipsToBounds = true
        addSubview(topBoundaryView)
        addSubview(bottomBoundaryView)
        setupGestures()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        displayLink?.invalidate()
        pageTasks.values.forEach { $0.task.cancel() }
    }

    /// 手指接触页面时结束上一段惯性，并低频提交其最终稳定页。
    override func touchesBegan(
        _ touches: Set<UITouch>,
        with event: UIEvent?,
    ) {
        if isUserScrollSequenceActive {
            reportCurrentPageIfNeeded(force: true)
            reportStablePageIfNeeded()
            isUserScrollSequenceActive = false
        }
        stopDisplayLink()
        super.touchesBegan(touches, with: event)
    }

    /// 更新通用页面清单；相同 identity 不重置 Canvas 或重复请求。
    func configure(
        snapshot: ReaderCanvasSnapshot,
        pageAccess: ReaderPageAccess,
        chromeTapCount: Int,
        events: ReaderCanvasEvents,
    ) {
        guard !isStopped else { return }

        self.pageAccess = pageAccess
        if chromeTapGesture?.numberOfTapsRequired != chromeTapCount {
            chromeTapGesture?.numberOfTapsRequired = chromeTapCount
        }
        onReachTop = events.onReachTop
        onReachBottom = events.onReachBottom
        onRetryTopBoundary = events.onRetryTopBoundary
        onRetryBottomBoundary = events.onRetryBottomBoundary
        onCurrentPageChange = events.onCurrentPageChange
        onStablePageChange = events.onStablePageChange
        onScrollRequestHandled = events.onScrollRequestHandled
        onTap = events.onTap
        onScrollStart = events.onScrollStart
        updateImageDisplayModeIfNeeded()

        if let scrollRequest = snapshot.scrollRequest,
           scrollRequest.id != handledScrollRequestID {
            pendingScrollRequest = scrollRequest
        }

        if configuredContentVersion != snapshot.contentVersion {
            if let configuredContentVersion,
               configuredContentVersion >= snapshot.replacementVersion {
                expandPagesPreservingOffset(snapshot.pages)
            } else {
                replacePages(snapshot.pages)
            }
            configuredContentVersion = snapshot.contentVersion
        }

        // 页面扩展必须先于边界占位项消失：如果用户正停在 150pt 占位范围内，
        // 新页面可以接替原有局部坐标，避免先收回边界造成一次位置跳动。
        updateChapterBoundaryPresentations(
            top: snapshot.topBoundaryPresentation,
            bottom: snapshot.bottomBoundaryPresentation,
        )

        guard bounds.width > 0,
              bounds.height > 0
        else {
            return
        }

        let didApplyScrollRequest = applyPendingScrollRequestIfNeeded()
        // 控制栏、主题等 SwiftUI 更新仍同步回调，但不重复规划未变化的页面窗口。
        if needsRender || didApplyScrollRequest {
            updatePageWindow(force: didApplyScrollRequest)
            needsRender = false
        }
        reportPendingStablePageIfNeeded()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0,
              bounds.height > 0,
              bounds != lastLayoutBounds
        else {
            return
        }

        lastLayoutBounds = bounds
        updateImageDisplayModeIfNeeded()
        layoutNodes()
        let didApplyScrollRequest = applyPendingScrollRequestIfNeeded()
        if !didApplyScrollRequest {
            reapplyActiveScrollAnchorIfNeeded()
        }
        clampScrollAnchor()
        needsRender = true
        updatePageWindow(force: true)
        reportPendingStablePageIfNeeded()
        needsRender = false
    }
}

/// `CADisplayLink` 使用弱引用代理，避免与 Canvas 形成循环引用。
@MainActor
final class ReaderCanvasDisplayLinkProxy: NSObject {
    weak var target: ReaderCanvasUIView?

    /// 将屏幕刷新事件转发给仍然存活的 Canvas。
    @objc func tick(_ displayLink: CADisplayLink) {
        target?.handleDisplayLink(displayLink)
    }
}

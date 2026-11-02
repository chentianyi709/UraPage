import SwiftUI
import UIKit

/// 把来源无关的页面清单和加载能力装配到固定视口 Canvas。
struct ReaderCanvasView: UIViewRepresentable {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    let snapshot: ReaderCanvasSnapshot
    let pageAccess: ReaderPageAccess
    let chromeTapCount: Int
    let events: ReaderCanvasEvents
    let session: ReaderSession

    /// 使用来源无关的页面能力创建 Canvas；单章来源可省略章节边界回调。
    init(
        snapshot: ReaderCanvasSnapshot,
        pageAccess: ReaderPageAccess,
        chromeTapCount: Int,
        events: ReaderCanvasEvents,
        session: ReaderSession,
    ) {
        self.snapshot = snapshot
        self.pageAccess = pageAccess
        self.chromeTapCount = chromeTapCount
        self.events = events
        self.session = session
    }

    /// 创建由 UIKit 管理虚拟偏移和节点复用的 Canvas。
    func makeUIView(context _: Context) -> ReaderCanvasUIView {
        let view = ReaderCanvasUIView(
            pageImageLoader: session.pageImageLoader,
        )
        session.attachCanvas(view)
        view.overrideUserInterfaceStyle = userInterfaceStyle
        return view
    }

    /// 保存 Reader 是否真正进入过后台，避免首次创建 Canvas 时误触发恢复。
    func makeCoordinator() -> Coordinator {
        Coordinator(session: session)
    }

    /// 只传入通用页面值和页面数据加载能力。
    func updateUIView(
        _ uiView: ReaderCanvasUIView,
        context: Context,
    ) {
        if uiView.overrideUserInterfaceStyle != userInterfaceStyle {
            uiView.overrideUserInterfaceStyle = userInterfaceStyle
        }
        uiView.configure(
            snapshot: snapshot,
            pageAccess: pageAccess,
            chromeTapCount: chromeTapCount,
            events: events,
        )

        switch scenePhase {
        case .background:
            context.coordinator.shouldRecoverPageLoadsAfterActivation = true

        case .active:
            guard context.coordinator.shouldRecoverPageLoadsAfterActivation else {
                return
            }

            context.coordinator.shouldRecoverPageLoadsAfterActivation = false
            uiView.recoverPageLoadsAfterAppBecomesActive()

        case .inactive:
            break

        @unknown default:
            break
        }
    }

    /// 把 SwiftUI Reader 颜色模式同步给内部 UIKit Canvas。
    private var userInterfaceStyle: UIUserInterfaceStyle {
        colorScheme == .dark ? .dark : .light
    }

    /// Reader 销毁时停止惯性并取消全部窗口页面请求。
    static func dismantleUIView(
        _ uiView: ReaderCanvasUIView,
        coordinator: Coordinator,
    ) {
        coordinator.session.detachCanvas(uiView)
    }

    /// 记录一次后台经历，供回到前台时执行单次页面恢复。
    final class Coordinator {
        let session: ReaderSession
        var shouldRecoverPageLoadsAfterActivation = false

        /// 保留当前 ReaderSession，确保 dismantle 能回收页面任务。
        init(session: ReaderSession) {
            self.session = session
        }
    }
}

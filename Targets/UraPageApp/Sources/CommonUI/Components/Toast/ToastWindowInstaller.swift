import SwiftUI
import UIKit

/// 把 Toast 安装到当前 Scene 的独立高层 Window，避免被 Sheet 或全屏展示遮挡。
struct ToastWindowInstaller: UIViewRepresentable {
    @Environment(\.colorScheme) private var colorScheme

    /// 使用 Coordinator 持有 Window 生命周期。
    func makeCoordinator() -> Coordinator {
        Coordinator(colorScheme: colorScheme)
    }

    /// 创建一个零尺寸 Scene 解析 View，进入层级后安装 Toast Window。
    func makeUIView(context: Context) -> ToastWindowSceneResolverView {
        let view = ToastWindowSceneResolverView()
        view.onResolveScene = { [weak coordinator = context.coordinator] scene in
            coordinator?.attach(to: scene)
        }
        return view
    }

    /// SwiftUI 刷新时重新确认当前 Scene。
    func updateUIView(
        _ uiView: ToastWindowSceneResolverView,
        context: Context,
    ) {
        context.coordinator.update(colorScheme: colorScheme)
        uiView.resolveSceneIfPossible()
    }

    /// Installer 离开层级时释放它持有的额外 Window。
    static func dismantleUIView(
        _ uiView: ToastWindowSceneResolverView,
        coordinator: Coordinator,
    ) {
        uiView.onResolveScene = nil
        coordinator.detach()
    }

    /// 持有当前 Toast Window，并确保同一 Scene 只安装一次。
    @MainActor
    final class Coordinator {
        private var colorScheme: ColorScheme
        private var hostingController: UIHostingController<ToastHost>?
        private var window: ToastPassthroughWindow?

        init(colorScheme: ColorScheme) {
            self.colorScheme = colorScheme
        }

        /// 主 App 强制主题变化时，同步刷新独立 Window 的 SwiftUI 根视图。
        func update(colorScheme: ColorScheme) {
            guard colorScheme != self.colorScheme else {
                return
            }

            self.colorScheme = colorScheme
            hostingController?.rootView = ToastHost(colorScheme: colorScheme)
        }

        /// 在当前 Scene 中创建高于系统 Sheet 的透明 Window。
        func attach(to scene: UIWindowScene) {
            if window?.windowScene === scene {
                return
            }

            detach()

            let hostingController = UIHostingController(
                rootView: ToastHost(colorScheme: colorScheme),
            )
            hostingController.view.backgroundColor = .clear

            let toastWindow = ToastPassthroughWindow(windowScene: scene)
            toastWindow.rootViewController = hostingController
            toastWindow.backgroundColor = .clear
            toastWindow.windowLevel = UIWindow.Level(
                rawValue: UIWindow.Level.alert.rawValue + 1,
            )
            toastWindow.isToastVisible = {
                ToastCenter.shared.message != nil
            }
            toastWindow.isHidden = false

            self.hostingController = hostingController
            window = toastWindow
        }

        /// 隐藏并释放已安装的 Toast Window。
        func detach() {
            window?.isHidden = true
            window?.rootViewController = nil
            hostingController = nil
            window = nil
        }
    }
}

/// 在 UIViewRepresentable 进入 Window 层级后提供当前 UIWindowScene。
final class ToastWindowSceneResolverView: UIView {
    var onResolveScene: ((UIWindowScene) -> Void)?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        resolveSceneIfPossible()
    }

    /// 只在 View 已经所属某个 Scene 时回传结果。
    func resolveSceneIfPossible() {
        guard let windowScene = window?.windowScene else {
            return
        }

        onResolveScene?(windowScene)
    }
}

/// 只在 Toast 横幅所在的顶部区域接收拖动，其余触摸穿透到底下的 Sheet 或页面。
private final class ToastPassthroughWindow: UIWindow {
    var isToastVisible: (() -> Bool)?

    override func hitTest(
        _ point: CGPoint,
        with event: UIEvent?,
    ) -> UIView? {
        guard isToastVisible?() == true else {
            return nil
        }

        let horizontalInset: CGFloat = 10
        let maximumInteractiveY = safeAreaInsets.top + 84
        guard point.x >= horizontalInset,
              point.x <= bounds.width - horizontalInset,
              point.y <= maximumInteractiveY
        else {
            return nil
        }

        return super.hitTest(point, with: event)
    }
}

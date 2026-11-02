import SwiftUI
import UIKit

extension View {
    /// 按 Reader 当前状态启用或禁用任意位置右滑返回。
    func restoresReaderInteractivePopGesture(
        isEnabled: Bool = true,
    ) -> some View {
        background(
            ReaderInteractivePopGestureRestorer(isEnabled: isEnabled),
        )
    }
}

/// 按 Reader 设置控制系统边缘与全屏返回，退出后恢复原状态。
private struct ReaderInteractivePopGestureRestorer: UIViewControllerRepresentable {
    let isEnabled: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIViewController(context: Context) -> HostingController {
        let controller = HostingController()
        controller.onAttach = { navigationController in
            context.coordinator.configure(
                navigationController,
                isEnabled: isEnabled,
            )
        }
        return controller
    }

    func updateUIViewController(_ controller: HostingController, context: Context) {
        controller.onAttach = { navigationController in
            context.coordinator.configure(
                navigationController,
                isEnabled: isEnabled,
            )
        }
        context.coordinator.configure(
            controller.navigationController,
            isEnabled: isEnabled,
        )
    }

    static func dismantleUIViewController(
        _: HostingController,
        coordinator: Coordinator,
    ) {
        coordinator.teardown()
    }

    final class HostingController: UIViewController {
        var onAttach: ((UINavigationController?) -> Void)?

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            onAttach?(navigationController)
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            onAttach?(navigationController)
        }
    }

    /// 接管系统手势的开始条件，保留 UIKit 的交互式转场和手势关联。
    /// 仅打开 isEnabled 不足以恢复隐藏导航栏后的返回，原 delegate 仍可能拒绝手势。
    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        private weak var navigationController: UINavigationController?
        private var isEnabled = false
        private var originalStates: [(
            gesture: UIGestureRecognizer,
            isEnabled: Bool,
            delegate: (any UIGestureRecognizerDelegate)?,
        )] = []

        func configure(_ navigationController: UINavigationController?, isEnabled: Bool) {
            guard let navigationController else { return }

            if self.navigationController !== navigationController {
                teardown()
                self.navigationController = navigationController
                originalStates = [
                    navigationController.interactivePopGestureRecognizer,
                    navigationController.interactiveContentPopGestureRecognizer,
                ].compactMap { gesture in
                    gesture.map { (gesture: $0, isEnabled: $0.isEnabled, delegate: $0.delegate) }
                }
            }
            self.isEnabled = isEnabled
            for state in originalStates {
                // Toolbar 显隐可能重设系统手势；每次布局时按 Reader 当前设置重新安装。
                state.gesture.delegate = self
                state.gesture.isEnabled = isEnabled
            }
        }

        /// 系统返回手势自行判断方向；这里只排除禁用、根页和进行中的转场。
        func gestureRecognizerShouldBegin(_: UIGestureRecognizer) -> Bool {
            // 系统内容返回手势可能在速度仍为零时询问 delegate；再次按速度筛选会提前拒绝右滑。
            guard isEnabled, let navigationController else { return false }

            return navigationController.viewControllers.count > 1
                && navigationController.transitionCoordinator == nil
        }

        func teardown() {
            for state in originalStates {
                state.gesture.delegate = state.delegate
                state.gesture.isEnabled = state.isEnabled
            }
            originalStates.removeAll()
            navigationController = nil
            isEnabled = false
        }
    }
}

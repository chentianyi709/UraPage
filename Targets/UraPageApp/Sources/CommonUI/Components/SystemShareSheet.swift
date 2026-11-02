import SwiftUI
import UIKit

/// 系统分享面板：把导出的压缩包或单张图片交给用户存储到「文件」或分享给其它 App。
///
/// `UIActivityViewController` 没有 SwiftUI 对应控件，这里做最小适配并把职责限制在展示上；
/// 面板关闭（完成或取消）时回调是否完成与所选渠道标识，由调用方清理临时产物并按渠道提示。
struct SystemShareSheet: UIViewControllerRepresentable {
    let url: URL

    /// 面板关闭回调：`completed` 表示用户完成分享（取消为 false），`activityIdentifier` 是所选渠道的 rawValue。
    let onFinish: (_ completed: Bool, _ activityIdentifier: String?) -> Void

    func makeUIViewController(context _: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        controller.completionWithItemsHandler = { activityType, completed, _, _ in
            onFinish(completed, activityType?.rawValue)
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context _: Context) {}
}

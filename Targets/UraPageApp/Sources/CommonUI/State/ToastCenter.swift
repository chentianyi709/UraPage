import Foundation
import Observation
import SwiftUI
import UIKit

/// Toast 的视觉语义与触觉反馈类型。
enum ToastType: Hashable, Sendable {
    case success
    case error
    case info
    case warning
}

/// 一条待展示的 Toast 内容。
struct ToastMessage: Identifiable, Equatable, Sendable {
    let id = UUID()
    let text: String
    let type: ToastType
}

/// App 进程内唯一的短暂反馈中心：串行展示一条 Toast，固定时间后自动关闭。
///
/// 用进程单例：任何页面直接 `ToastCenter.shared.show(…)`，不经过环境注入。
/// 展示落在独立的高层 Window（见 `ToastWindowInstaller`），因此不会被 Sheet 遮挡。
@Observable
@MainActor
final class ToastCenter {
    /// App 进程内唯一实例。
    static let shared = ToastCenter()

    /// 当前正在展示的 Toast；新消息会直接替换旧消息。
    private(set) var message: ToastMessage?

    /// 持有当前自动关闭任务，新消息或手势关闭时取消。
    @ObservationIgnored
    private var dismissTask: Task<Void, Never>?

    private init() {}

    /// 展示一条 Toast，并在固定时间后自动关闭。
    func show(_ text: String, type: ToastType = .info) {
        dismissTask?.cancel()
        triggerHaptic(for: type)

        withAnimation(.spring(response: 0.24, dampingFraction: 0.76)) {
            message = ToastMessage(text: text, type: type)
        }
        // Toast 取代了部分页面内联错误文本，需要主动播报，确保 VoiceOver 用户同样能获得结果。
        UIAccessibility.post(notification: .announcement, argument: text)

        dismissTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .seconds(2.4))
            } catch {
                return
            }

            guard let self else {
                return
            }

            dismissTask = nil
            withAnimation(.spring(response: 0.2, dampingFraction: 0.9)) {
                message = nil
            }
        }
    }

    /// 立即关闭当前 Toast，供上滑手势使用。
    func dismiss() {
        dismissTask?.cancel()
        dismissTask = nil
        withAnimation(.spring(response: 0.2, dampingFraction: 0.9)) {
            message = nil
        }
    }

    /// 根据消息语义触发与系统通知一致的触觉反馈。
    private func triggerHaptic(for type: ToastType) {
        switch type {
        case .success:
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .error:
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        case .warning:
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        case .info:
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }
}

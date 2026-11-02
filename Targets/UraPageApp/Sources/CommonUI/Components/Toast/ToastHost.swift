import SwiftUI

/// 在 App 独立 Toast Window 顶部展示当前横幅。
struct ToastHost: View {
    let colorScheme: ColorScheme

    var body: some View {
        VStack {
            if let message = ToastCenter.shared.message {
                ToastBanner(
                    message: message,
                    onDismiss: { ToastCenter.shared.dismiss() },
                )
                .id(message.id)
                .transition(
                    .asymmetric(
                        insertion: .offset(y: -44)
                            .combined(with: .opacity)
                            .combined(with: .scale(scale: 0.64, anchor: .top)),
                        removal: .offset(y: -52)
                            .combined(with: .opacity)
                            .combined(with: .scale(scale: 0.82, anchor: .top)),
                    ),
                )
            }

            Spacer()
        }
        .safeAreaPadding(.top, 8)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // 独立 Window 不会自动继承主 SwiftUI 树的强制主题，需要明确同步。
        .environment(\.colorScheme, colorScheme)
    }
}

/// 绘制一条可跟随手指上移并拖动关闭的 Toast 横幅。
private struct ToastBanner: View {
    @State private var verticalOffset: CGFloat = 0

    let message: ToastMessage
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(iconColor.opacity(0.16))
                    .frame(width: 36, height: 36)

                Image(systemName: iconName)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(iconColor)
            }

            Text(message.text)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 13)
        .frame(maxWidth: .infinity, minHeight: 58)
        .background {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.clear)
                .shadow(color: .black.opacity(0.16), radius: 24, x: 0, y: 12)
        }
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(.white.opacity(0.16), lineWidth: 0.5)
        }
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .offset(y: verticalOffset)
        .gesture(dismissGesture)
    }

    /// 只跟随向上的拖动；超过阈值或快速上甩时关闭横幅。
    private var dismissGesture: some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .global)
            .onChanged { value in
                verticalOffset = min(0, value.translation.height)
            }
            .onEnded { value in
                let shouldDismiss = value.translation.height <= -28
                    || value.predictedEndTranslation.height <= -52
                guard !shouldDismiss else {
                    onDismiss()
                    return
                }

                withAnimation(.spring(response: 0.22, dampingFraction: 0.82)) {
                    verticalOffset = 0
                }
            }
    }

    /// 返回当前 Toast 语义对应的 SF Symbol。
    private var iconName: String {
        switch message.type {
        case .success:
            "checkmark.circle.fill"
        case .error:
            "xmark.circle.fill"
        case .info:
            "info.circle.fill"
        case .warning:
            "exclamationmark.triangle.fill"
        }
    }

    /// 返回当前 Toast 语义对应的图标颜色。
    private var iconColor: Color {
        switch message.type {
        case .success:
            .green
        case .error:
            .red
        case .info:
            .blue
        case .warning:
            .orange
        }
    }
}

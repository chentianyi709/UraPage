import SwiftUI

/// 使用 App 插图统一展示可重试的首屏加载失败状态。
struct LoadErrorView: View {
    let title: String
    let message: String
    let retryTitle: String
    let onRetry: () -> Void

    /// 创建包含错误说明和同步重试操作的加载失败状态。
    init(
        title: String = "加载失败",
        message: String,
        retryTitle: String = "重新加载",
        onRetry: @escaping () -> Void,
    ) {
        self.title = title
        self.message = message
        self.retryTitle = retryTitle
        self.onRetry = onRetry
    }

    var body: some View {
        VStack(spacing: 14) {
            Image(.errorState)
                .resizable()
                .scaledToFit()
                .frame(width: 200, height: 150)
                .accessibilityHidden(true)

            Text(title)
                .font(.headline)
                .foregroundStyle(Color.textPrimary)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)

            Button(retryTitle, action: onRetry)
                .buttonStyle(.borderedProminent)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
    }
}

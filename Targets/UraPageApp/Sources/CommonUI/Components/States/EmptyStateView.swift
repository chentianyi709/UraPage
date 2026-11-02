import SwiftUI

/// 使用 App 插图统一展示没有可用内容的页面状态。
struct EmptyStateView: View {
    /// 状态插图；空数据、搜索与未登录共用同一版式，只替换插图。
    enum Illustration {
        case empty
        case login
        case search
    }

    /// 标题；为 `nil` 时不显示（例如只保留说明与操作的页面）。
    let title: String?

    /// 说明文案；为 `nil` 时不显示。
    let message: String?

    /// 展示的插图。
    let illustration: Illustration

    init(title: String? = nil, message: String? = nil, illustration: Illustration = .empty) {
        self.title = title
        self.message = message
        self.illustration = illustration
    }

    var body: some View {
        VStack(spacing: 14) {
            Image(illustrationImage)
                .resizable()
                .scaledToFit()
                // 插图统一按 3:2（600×400）导出；容器同比例，避免 `scaledToFit` 上下留白拉大图文间距。
                .frame(width: 200, height: 200 * 2 / 3)
                .accessibilityHidden(true)

            if let title {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(Color.textPrimary)
            }

            if let message {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(24)
    }

    private var illustrationImage: ImageResource {
        switch illustration {
        case .empty: .emptyState
        case .login: .loginState
        case .search: .searchState
        }
    }
}

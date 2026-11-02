import SwiftUI

/// 在分页列表底部统一展示加载中、失败重试或没有更多内容。
struct PaginationFooter: View {
    let isLoadingMore: Bool
    let canLoadMore: Bool
    let loadMoreErrorMessage: String?
    let onRetryLoadMore: @MainActor () -> Void

    /// 只有真实分页状态需要呈现时才保留底部高度。
    private var isVisible: Bool {
        isLoadingMore || loadMoreErrorMessage != nil || !canLoadMore
    }

    var body: some View {
        HStack(spacing: 8) {
            if isLoadingMore {
                ProgressView()
                    .controlSize(.small)

                Text("正在加载更多…")
                    .foregroundStyle(Color.textSecondary)
            } else if let loadMoreErrorMessage {
                Button(action: onRetryLoadMore) {
                    Text("加载更多失败，点击重试")
                        .foregroundStyle(.tint)
                }
                .buttonStyle(.plain)
                .accessibilityHint("重试加载下一页。错误信息：\(loadMoreErrorMessage)")
            } else if !canLoadMore {
                Text("没有更多了")
                    .foregroundStyle(Color.textTertiary)
            }
        }
        .font(.caption)
        .frame(maxWidth: .infinity)
        .padding(.vertical, isVisible ? 16 : 0)
        .accessibilityHidden(!isVisible)
    }
}

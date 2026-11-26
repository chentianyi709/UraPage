import SwiftUI

/// 分区级加载失败：整块替换该分区，就地重试。
///
/// 首页由多个独立接口组成，单个分区失败不该拖垮整页：失败的分区只重发自己的请求。
/// 失败块不保留分区标题——服务端给的分区名（如各分类名）有数据时才有意义，
/// 失败时用一个临时标题顶替会让标题跟着数据一起变。
struct SectionLoadFailureView: View {
    /// 失败分区的名称；只用于读屏，界面不展示。
    let title: String

    /// 展示用的错误说明。
    let message: String

    let onRetry: () -> Void

    var body: some View {
        SectionLoadFailureContent(
            message: message,
            horizontalPadding: ComicGridMetrics.horizontalPadding,
            onRetry: onRetry,
        )
        .accessibilityLabel("\(title)加载失败")
    }
}

/// 分区失败时的就地重试提示：只有提示与错误说明，标题由调用方自行决定是否展示。
///
/// 搜索页热门词与首页分区共用同一段文案和点击行为；两者的外层边距不同，
/// 因此水平内边距由调用方给出（首页分区补 `ComicGridMetrics.horizontalPadding`，
/// 搜索页外层已有统一的 16pt 边距）。
struct SectionLoadFailureContent: View {
    /// 展示用的错误说明。
    let message: String

    /// 内容左右内边距；同时计入点击命中区。
    var horizontalPadding: CGFloat = 0

    let onRetry: () -> Void

    var body: some View {
        Button(action: onRetry) {
            VStack(spacing: 6) {
                Text("加载失败，点击重试")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.textSecondary)

                Text(message)
                    .font(.caption)
                    .foregroundStyle(Color.textTertiary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, minHeight: 72)
            .padding(.horizontal, horizontalPadding)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityHint(message)
    }
}

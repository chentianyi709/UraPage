import SwiftUI

/// 分区级加载失败：保留分区标题与位置，就地重试。
///
/// 用于首页这类由多个独立接口组成、单个分区失败不应拖垮整页的场景：
/// 分区自己提示失败并只重发失败的请求；整页失败仍由 `LoadErrorView` 承担。
struct SectionLoadFailureView: View {
    /// 分区标题；失败时保留标题行，用户能看出是哪个分区失败，高度也与加载完成时一致。
    let title: String

    /// 展示用的错误说明。
    let message: String

    let onRetry: () -> Void

    var body: some View {
        ComicSection {
            ComicSectionHeader(title: title, showsDisclosureIndicator: false)
        } content: {
            SectionLoadFailureContent(
                message: message,
                horizontalPadding: ComicGridMetrics.horizontalPadding,
                onRetry: onRetry,
            )
        }
    }
}

/// 分区失败时的就地重试提示：标题由调用方所在的分区提供，这里只有提示与错误说明。
///
/// 搜索页热门词与首页分区共用同一段文案和点击行为；两者的标题样式与外层边距不同，
/// 因此水平内边距由调用方给出（首页分区由调用方补 `ComicGridMetrics.horizontalPadding`，
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

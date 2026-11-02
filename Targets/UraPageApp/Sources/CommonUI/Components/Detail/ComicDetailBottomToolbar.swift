import SwiftUI

/// 三来源详情页共用的底部操作顺序；按钮行为由来源页面接入。
///
/// 未接入的动作保持 `nil`，点击时不产生业务副作用；点赞按钮由是否存在 `onLike` 决定。
struct ComicDetailBottomToolbar: ToolbarContent {
    let showsOnlineActions: Bool
    let isLiked: Bool
    let isLiking: Bool
    let onLike: (() -> Void)?
    let onFavorite: (() -> Void)?
    let onDownload: (() -> Void)?
    let onChapters: (() -> Void)?
    let onComments: (() -> Void)?

    /// 该作品的下载状态；`nil` 表示未下载。用于切换下载图标与品牌色。
    var downloadState: DownloadState?

    var body: some ToolbarContent {
        if showsOnlineActions, let onLike {
            ToolbarItem(placement: .bottomBar) {
                if isLiking {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.brandPrimary)
                        .frame(width: 28, height: 28)
                        .accessibilityLabel(likeAccessibilityLabel)
                } else {
                    toolbarButton(
                        systemImage: isLiked ? "heart.fill" : "heart",
                        accessibilityLabel: likeAccessibilityLabel,
                        foregroundColor: isLiked ? .brandPrimary : .primary,
                        action: onLike,
                    )
                }
            }
        }

        if showsOnlineActions {
            ToolbarItem(placement: .bottomBar) {
                toolbarButton(systemImage: "bookmark", accessibilityLabel: "收藏", action: onFavorite)
            }

            ToolbarItem(placement: .bottomBar) {
                toolbarButton(
                    systemImage: downloadIsActive ? "arrow.down.circle.fill" : "arrow.down.circle",
                    accessibilityLabel: downloadAccessibilityLabel,
                    foregroundColor: downloadIsActive ? .brandPrimary : .primary,
                    isBlinking: downloadState == .downloading,
                    action: onDownload,
                )
            }
        }

        if showsOnlineActions || onChapters != nil {
            ToolbarSpacer(.flexible, placement: .bottomBar)
        }

        if let onChapters {
            ToolbarItem(placement: .bottomBar) {
                toolbarButton(systemImage: "books.vertical", accessibilityLabel: "查看章节", action: onChapters)
            }
        }

        if showsOnlineActions {
            ToolbarItem(placement: .bottomBar) {
                toolbarButton(systemImage: "bubble.left", accessibilityLabel: "查看评论", action: onComments)
            }
        }
    }

    /// 点赞请求进行中时提供准确的辅助功能说明。
    private var likeAccessibilityLabel: String {
        if isLiking {
            return isLiked ? "正在取消点赞" : "正在点赞"
        }
        return isLiked ? "已点赞" : "点赞"
    }

    /// 排队、处理中、暂停或已完成时下载图标用实心样式和品牌色。
    private var downloadIsActive: Bool {
        switch downloadState {
        case .some(.queued), .some(.downloading), .some(.paused), .some(.completed):
            true
        default:
            false
        }
    }

    /// 按下载状态给出准确的辅助功能说明。
    private var downloadAccessibilityLabel: String {
        switch downloadState {
        case .some(.queued):
            "等待下载"
        case .some(.downloading):
            "下载中"
        case .some(.paused):
            "下载已暂停"
        case .some(.completed):
            "已下载"
        case .some(.failed), .none:
            "下载"
        }
    }

    /// 公共底栏按钮；任务进行中的图标可通过 `isBlinking` 持续闪烁。
    private func toolbarButton(
        systemImage: String,
        accessibilityLabel: String,
        foregroundColor: Color = .primary,
        isBlinking: Bool = false,
        action: (() -> Void)?,
    ) -> some View {
        Button {
            action?()
        } label: {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(foregroundColor)
                .modifier(BlinkingSymbolEffect(isActive: isBlinking))
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .tint(.primary)
        .accessibilityLabel(accessibilityLabel)
    }
}

/// 让底栏图标在任务进行中持续闪烁；减少动态效果时保持常亮。
///
/// 实测符号效果（`.symbolEffect(.pulse)`）在系统底栏按钮中不产生动画，
/// 因此直接对透明度做重复动画，确保图标在底栏里也能看到状态变化。
private struct BlinkingSymbolEffect: ViewModifier {
    let isActive: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isDimmed = false

    func body(content: Content) -> some View {
        content
            .opacity(isDimmed ? 0.3 : 1)
            .onAppear { updateAnimation() }
            .onChange(of: isActive) { _, _ in updateAnimation() }
            .onChange(of: reduceMotion) { _, _ in updateAnimation() }
    }

    private func updateAnimation() {
        guard isActive, !reduceMotion else {
            withAnimation(.easeOut(duration: 0.2)) {
                isDimmed = false
            }
            return
        }

        withAnimation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true)) {
            isDimmed = true
        }
    }
}

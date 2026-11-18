import SwiftUI

/// 评论弹窗：只展示头像、名称、时间与正文，回复在行内展开。
///
/// 页面级 `sheet` 的内容；首屏、分页与按需回复都由 `ComicCommentsController` 持有，
/// 这里只负责呈现与转发点击。
struct ComicCommentsSheet: View {
    @Environment(\.dismiss) private var dismiss

    let controller: ComicCommentsController

    @State private var scrollPosition = ScrollPosition()

    var body: some View {
        NavigationStack {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.pageBackground)
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            Task {
                                await controller.reload()
                                // 骨架换回列表时 `ScrollView` 是新建的，但 `ScrollPosition` 会记住旧值，
                                // 显式归位才算真的回到顶部。
                                scrollPosition.scrollTo(y: 0)
                            }
                        } label: {
                            // 刷新中换成正圆 loading，箭头不再「不动地摆在那里」。
                            if controller.isReloading {
                                ProgressView()
                                    .controlSize(.small)
                                    .tint(Color.brandPrimary)
                            } else {
                                Image(systemName: "arrow.clockwise")
                            }
                        }
                        .accessibilityLabel(controller.isReloading ? "正在刷新评论" : "刷新评论")
                        .tint(.primary)
                        .disabled(controller.isReloading || controller.isLoadingMore)
                    }

                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                        }
                        .accessibilityLabel("关闭评论")
                        .tint(.primary)
                    }
                }
        }
        .task {
            // 只负责触发；请求由 controller 持有，不随这个视图的消失而取消。
            controller.loadIfNeeded()
        }
        // 与章节列表等弹窗同一套顶部过渡：内容滚到导航栏下方时渐隐模糊，而不是硬边。
        .appNavigationBarScrollEdgeEffect()
    }

    /// 已知总数时带上数量，否则只显示标题。
    private var title: String {
        controller.total > 0 ? "评论（\(controller.total)）" : "评论"
    }

    @ContentBuilder
    private var content: some View {
        switch controller.loadState {
        case .idle, .loading:
            ComicCommentsSkeleton()

        case let .failed(error):
            LoadErrorView(title: "评论加载失败", message: error.message) {
                Task { await controller.reload() }
            }
            .padding(.horizontal, 16)

        case .loaded:
            if controller.comments.isEmpty {
                emptyState
            } else {
                list
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("还没有评论", systemImage: "bubble.left")
        } description: {
            Text("这部作品暂时没有人留言")
        }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(controller.comments) { comment in
                    ComicCommentCard(comment: comment, controller: controller)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)

            // 与漫画列表共用同一个分页页脚：加载中／失败重试／没有更多了。
            if controller.showsPaginationFooter {
                PaginationFooter(
                    isLoadingMore: controller.isLoadingMore,
                    canLoadMore: controller.canLoadMoreComments,
                    loadMoreErrorMessage: controller.loadMoreErrorMessage,
                    onRetryLoadMore: {
                        Task { await controller.loadMoreIfNeeded() }
                    },
                )
                .padding(.horizontal, 16)
            }

            Color.clear
                .frame(height: 16)
        }
        .scrollPosition($scrollPosition)
        // 滚到底部附近自动续载；是否真的发请求由控制器的 canLoadMore／isLoadingMore 守卫。
        .onApproachingBottom(prefetchScreens: 1.6) {
            Task { await controller.loadMoreIfNeeded() }
        }
    }
}

/// 一条顶级评论：头像／名称／时间／正文，以及可展开的回复。
private struct ComicCommentCard: View {
    let comment: ComicComment
    let controller: ComicCommentsController

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                CommentAvatar(reference: comment.avatar, size: 38)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 6) {
                    Text(comment.nickname.isEmpty ? "匿名用户" : comment.nickname)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)

                    Text(comment.displayContent)
                        .font(.subheadline)
                        .foregroundStyle(Color.textPrimary)
                        .lineSpacing(3)
                        .textSelection(.enabled)

                    metaRow
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if isExpanded {
                repliesSection
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.surface)
                // 卡片紧挨着排（行距 12），阴影半径一大就会糊到相邻卡片上；收成贴着底边的一层。
                .shadow(color: .black.opacity(0.05), radius: 3, x: 0, y: 1)
        }
    }

    /// 正文下方的一行：时间在左，展开回复在右。
    ///
    /// 整行至少 20pt（caption 行高约 15，上下各留一点）、内容垂直居中：右侧在
    /// 「查看更多回复」和「正在加载中 + 图标」之间切换，行高只要跟着内容走，整张卡片就会往下跳一下。
    /// 用 `minHeight` 而不是固定高度：系统字号调大时文字可以自己长高，不会被压住。
    /// 时间和入口都为空时整行不占位（否则会多出一条空白）。
    @ContentBuilder
    private var metaRow: some View {
        if !comment.dateText.isEmpty || showsRepliesAction {
            HStack(alignment: .center, spacing: 8) {
                if !comment.dateText.isEmpty {
                    Text(comment.dateText)
                        .font(.caption2)
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }

                Spacer(minLength: 8)

                if showsRepliesAction {
                    repliesToggle
                }
            }
            .frame(minHeight: 20)
        }
    }

    /// 评论本身带回复，或来源支持按需请求回复时，才显示展开入口。
    private var showsRepliesAction: Bool {
        !comment.replies.isEmpty
            || (controller.supportsRemoteReplies && comment.replyCount > 0)
    }

    private var repliesToggle: some View {
        Button(action: toggleReplies) {
            HStack(spacing: 4) {
                Text(isLoadingReplies ? "正在加载中" : (isExpanded ? "收起回复" : "查看更多回复"))
                    // 文案直接替换：默认会交叉淡入淡出，点起来像文字闪了一下。
                    .contentTransition(.identity)

                if isLoadingReplies {
                    // 图标压到 12pt：小于 caption 行高，出现时不把这行撑高。
                    ProgressView()
                        .scaleEffect(0.5)
                        .frame(width: 12, height: 12)
                        .tint(Color.brandPrimary)
                }
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.brandPrimary)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    /// 远程回复正在请求。
    private var isLoadingReplies: Bool {
        remoteState?.isLoading ?? false
    }

    /// 回复要单独请求，且第一页还没取到。
    private var needsRemoteFirstPage: Bool {
        comment.replies.isEmpty
            && controller.supportsRemoteReplies
            && (remoteState?.page ?? 0) == 0
    }

    /// 已随评论返回的回复立即展开；需要单独请求的先显示加载态，取回后再展开。
    ///
    /// 展开与收起都在无动画事务里完成，文案和回复区一次性替换。
    private func toggleReplies() {
        // 请求在途时不响应第二次点击；控制器里也有同样的守卫，这里只是不再灰掉颜色。
        guard !isLoadingReplies else {
            return
        }

        if isExpanded {
            applyExpanded(false)
            return
        }

        guard needsRemoteFirstPage else {
            applyExpanded(true)
            return
        }

        // 失败也展开：让错误文案和「重试」落在回复区里，而不是静默退回原按钮。
        Task {
            await controller.loadReplies(commentID: comment.id)
            applyExpanded(true)
        }
    }

    private func applyExpanded(_ expanded: Bool) {
        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction) {
            isExpanded = expanded
        }
    }

    private var remoteState: ComicCommentsController.ReplyState? {
        controller.replies[comment.id]
    }

    private var displayedReplies: [ComicComment] {
        comment.replies.isEmpty ? remoteState?.comments ?? [] : comment.replies
    }

    @ContentBuilder
    private var repliesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(displayedReplies) { reply in
                ComicCommentReplyRow(reply: reply)
            }

            if let remoteState, remoteState.hasVisibleStatus {
                remoteRepliesStatus(remoteState)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 48)
    }

    /// 单独请求回复时的加载、失败与「加载更多」。三种状态同高，切换时不顶动展开区。
    @ContentBuilder
    private func remoteRepliesStatus(_ state: ComicCommentsController.ReplyState) -> some View {
        if state.isLoading {
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
        } else if let message = state.errorMessage {
            HStack(spacing: 8) {
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(Color.textSecondary)

                Button("重试") {
                    Task { await controller.retryReplies(commentID: comment.id) }
                }
                .font(.caption2.weight(.semibold))
            }
            .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
        } else if state.canLoadMore {
            Button("加载更多回复") {
                Task { await controller.loadMoreReplies(commentID: comment.id) }
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(Color.brandPrimary)
            .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
        }
    }
}

/// 顶级评论下的一条回复；比顶级评论更紧凑。
private struct ComicCommentReplyRow: View {
    let reply: ComicComment

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            CommentAvatar(reference: reply.avatar, size: 26)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text(reply.nickname.isEmpty ? "匿名用户" : reply.nickname)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)
                        .layoutPriority(1)

                    // 只有绅士的页面结构带被回复人；其余来源没有这条信息就不显示。
                    if let target = reply.replyTargetName {
                        Text("回复 @\(target)")
                            .font(.caption2)
                            .foregroundStyle(Color.textSecondary)
                            .lineLimit(1)
                    }
                }

                Text(reply.displayContent)
                    .font(.caption)
                    .foregroundStyle(Color.textPrimary)
                    .lineSpacing(2)
                    .textSelection(.enabled)

                if !reply.dateText.isEmpty {
                    Text(reply.dateText)
                        .font(.caption2)
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .background(
            Color.pageBackground.opacity(0.6),
            in: RoundedRectangle(cornerRadius: 10),
        )
    }
}

/// 评论头像；没有引用或引用不可用时显示占位。
private struct CommentAvatar: View {
    let reference: ComicImageReference?
    let size: CGFloat

    var body: some View {
        Group {
            if let reference {
                ComicImageView(
                    reference: reference,
                    targetSize: CGSize(width: size, height: size),
                )
            } else {
                Circle()
                    .fill(Color.surfaceElevated)
                    .overlay {
                        Image(systemName: "person.fill")
                            .font(.system(size: size * 0.44, weight: .semibold))
                            .foregroundStyle(Color.iconSecondary)
                    }
            }
        }
        .frame(width: size, height: size)
        .clipShape(.circle)
    }
}

/// 评论首屏骨架：与真实卡片同一套头像、名称、正文与底部信息占位。
///
/// 张数按一屏能放下的量给足（八张），避免加载期间屏幕下半截露白；
/// 卡片高度也对齐真实卡片（名称 + 两行正文 + 一行底部信息），
/// 这样数据到了只是内容替换，不会把列表整体往下推。
private struct ComicCommentsSkeleton: View {
    /// 一屏约八张，多出的一点点被裁掉，比只给三张更像「内容在路上」。
    private static let cardCount = 8

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                ForEach(0 ..< Self.cardCount, id: \.self) { _ in
                    card
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .skeletonLoadingEffect()
        }
        // 骨架只是占位，滚动没有意义；避免加载期间把占位卡拖来拖去。
        .scrollDisabled(true)
    }

    private var card: some View {
        HStack(alignment: .top, spacing: 10) {
            SkeletonBlock(width: 38, height: 38, cornerRadius: 19)

            VStack(alignment: .leading, spacing: 8) {
                SkeletonBlock(width: 96, height: 14, cornerRadius: 4)
                SkeletonBlock(height: 12, cornerRadius: 4)
                SkeletonBlock(width: 180, height: 12, cornerRadius: 4)
                SkeletonBlock(width: 72, height: 10, cornerRadius: 4)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.surface)
        }
    }
}

private extension ComicComment {
    /// 正文展示文案；空正文用一个空格占位。
    ///
    /// `Text("")` 会被压成零高度，空评论的卡片就比别的矮一行。
    /// 评论固定占一行比省掉这一行更好读：卡片高度一致，扫读时视线不会被带偏。
    /// 三个来源在映射时都已 trim，所以 `isEmpty` 足以判断正文是否为空。
    var displayContent: String {
        content.isEmpty ? " " : content
    }
}

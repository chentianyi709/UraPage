/// 下载选章弹窗的一项：章节身份 + 展示标题 + 当前下载状态。
///
/// 由详情页把本源章节映射成该值传入；下载层不重新判定单章/多章。
struct DownloadChapterSelectionItem: Identifiable, Hashable {
    let identity: ChapterIdentity
    let title: String
    let order: Int

    /// 当前下载状态；`nil` 表示尚未下载。
    let state: DownloadState?

    var id: ChapterIdentity {
        identity
    }

    /// 只有「未下载」或「失败（可重试）」的章节能勾选；
    /// 排队、下载、暂停和完成中的章节不可再选。
    var isSelectable: Bool {
        state == nil || state == .failed
    }

    /// 下载状态的 VoiceOver 描述；未下载时为 `nil`。
    var accessibilityStatus: String? {
        switch state {
        case nil:
            nil
        case .queued:
            "排队中"
        case .downloading:
            "下载中"
        case .paused:
            "已暂停"
        case .completed:
            "已下载"
        case .failed:
            "下载失败"
        }
    }
}

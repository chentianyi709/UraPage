/// 单个章节下载记录的 Sendable 快照；由持久化层投影，供上层读取。
///
/// 只暴露身份、标题与状态；进度是运行时的单位计数，不落库。
struct ChapterDownloadRecord: Identifiable, Hashable, Sendable {
    let identity: ChapterIdentity
    let title: String
    let order: Int
    let state: DownloadState

    var id: ChapterIdentity {
        identity
    }

    /// 映射为下载选章弹窗的条目（复用同一套可选性与状态文案）。
    var selectionItem: DownloadChapterSelectionItem {
        DownloadChapterSelectionItem(
            identity: identity,
            title: title,
            order: order,
            state: state,
        )
    }
}

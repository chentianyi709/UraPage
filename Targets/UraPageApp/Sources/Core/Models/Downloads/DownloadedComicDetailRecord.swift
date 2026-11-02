/// 离线详情读取结果：组装后的作品展示值与下载状态已完成的章节元信息。
struct DownloadedComicDetailRecord: Sendable {
    let detail: DownloadedComicDetailSnapshot
    let chapters: [ChapterDownloadRecord]
}

/// 一个可离线打开的章节；页面身份来自本地 manifest，章节可用性由下载状态决定。
struct DownloadedChapterSnapshot: Identifiable, Hashable, Sendable {
    let identity: ChapterIdentity
    let title: String
    let order: Int
    let totalPageCount: Int
    let pages: [ComicPage]

    var id: ChapterIdentity {
        identity
    }
}

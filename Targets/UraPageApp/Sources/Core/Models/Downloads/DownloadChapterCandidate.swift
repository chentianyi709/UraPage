/// 详情页可下载的一个章节（本源章节到公共下载层的映射值）。
///
/// `order` 取目录原始下标；弹窗/请求都按它排序与回填。来源只负责把本源章节映射成该值。
struct DownloadChapterCandidate: Identifiable, Hashable, Sendable {
    let identity: ChapterIdentity
    let title: String
    let order: Int

    var id: ChapterIdentity {
        identity
    }
}

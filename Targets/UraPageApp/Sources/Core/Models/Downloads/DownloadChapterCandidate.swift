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

extension Array {
    /// 按数组顺序生成章节候选：`order` 取下标，保证与来源给的阅读顺序一致。
    ///
    /// 三个来源的章节类型各不相同，只有「身份 + 标题 + 顺序」这一步完全一样，
    /// 放在这里省掉每处重复的 `enumerated().map`。
    func downloadChapterCandidates(
        identity: (Element) -> ChapterIdentity,
        title: (Element) -> String,
    ) -> [DownloadChapterCandidate] {
        enumerated().map {
            DownloadChapterCandidate(
                identity: identity($0.element),
                title: title($0.element),
                order: $0.offset,
            )
        }
    }
}

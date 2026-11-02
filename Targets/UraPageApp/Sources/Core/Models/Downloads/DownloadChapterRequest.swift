/// 详情页向统一下载入口提交的单章请求。
///
/// 章节标题与顺序取自详情已有数据（与章节弹窗显示逻辑一致，下载层不重新判定单章/多章）；
/// 详情展示值随请求带上，入队时拆成作品行列（标题／作者／封面引用）与离线详情冷字段；
/// 相关推荐与在线操作状态不进入。封面是远程引用；下载层将其作为作品的独立图片资源保存，
/// 不计入章节进度，只参与作品完成判定。
struct DownloadChapterRequest: Hashable, Sendable {
    let identity: ChapterIdentity
    let chapterTitleSnapshot: String
    let chapterOrderSnapshot: Int
    let comicSnapshot: DownloadedComicDetailSnapshot

    init(
        identity: ChapterIdentity,
        chapterTitleSnapshot: String,
        chapterOrderSnapshot: Int,
        comicSnapshot: DownloadedComicDetailSnapshot,
    ) {
        self.identity = identity
        self.chapterTitleSnapshot = chapterTitleSnapshot
        self.chapterOrderSnapshot = chapterOrderSnapshot
        self.comicSnapshot = comicSnapshot
    }
}

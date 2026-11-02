/// 保存哔咔详情页展示和打开 Reader 所需的最小章节信息。
struct BikaComicChapter: Identifiable, Hashable, Sendable {
    let identity: ChapterIdentity
    let title: String

    var id: ChapterIdentity {
        identity
    }

    /// 使用接口可直接请求阅读内容的 `order` 建立章节身份。
    init(comicIdentity: ComicIdentity, title: String, order: Int) {
        identity = ChapterIdentity(comic: comicIdentity, chapterID: String(order))
        self.title = title
    }

    /// 从下载记录恢复原始章节身份；离线章节 ID 不根据展示顺序重新推导。
    init(identity: ChapterIdentity, title: String) {
        self.identity = identity
        self.title = title
    }
}

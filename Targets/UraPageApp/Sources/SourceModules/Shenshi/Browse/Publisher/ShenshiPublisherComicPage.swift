/// 一页发布者投稿漫画及网页提供的下一页游标。
struct ShenshiPublisherComicPage: Sendable {
    let items: [ComicListItem]
    let nextCursor: String?
}

/// 保存禁漫详情页当前只读展示需要的数据。
struct JMComicDetail: ComicDetailContentProviding {
    let identity: ComicIdentity
    let title: String
    let authors: [String]
    let viewCount: Int
    let likeCount: Int
    let isLiked: Bool
    let commentCount: Int
    let publishedDateText: String?
    let summary: String
    let tags: [String]
    let pageCount: Int?
    let chapters: [JMComicChapter]
    let cover: ComicImageSource
    let relatedComics: [ComicListItem]

    /// 旧版只为多章节作品提供目录入口；单章节直接从阅读入口进入。
    var showsChaptersButton: Bool {
        chapters.count > 1
    }

    /// 单话作品没有目录；`/comic_read` 使用作品 ID 作为章节 ID。
    var readerChapters: [JMComicChapter] {
        if !chapters.isEmpty {
            return chapters
        }

        return [JMComicChapter(
            identity: ChapterIdentity(comic: identity, chapterID: identity.comicID),
            title: title,
        )]
    }

    /// 向统一作者行提供禁漫返回的全部作者名称。
    var authorNames: [String] {
        authors
    }

    /// 禁漫详情只有一组标签，没有分类页。
    var tagGroups: [ComicTagGroup] {
        [ComicTagGroup(kind: .tag, values: tags)]
    }

    /// 浏览、点赞、图片与日期；服务端没给图片数时这一项不出现。
    var fields: [ComicDetailField] {
        [
            .viewCount(viewCount),
            .likeCount(likeCount),
            pageCount.map(ComicDetailField.pageCount),
            publishedDateText.flatMap(ComicDetailField.publishedDate),
        ].compactMap(\.self)
    }
}

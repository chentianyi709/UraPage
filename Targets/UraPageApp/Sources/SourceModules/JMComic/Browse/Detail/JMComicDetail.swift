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

    /// 向统一字段行提供禁漫需要展示的统计、日期与图片数量（服务端返回 `total_photos` 时）。
    var metadata: ComicDetailMetadata {
        ComicDetailMetadata(
            viewCount: viewCount,
            likeCount: likeCount,
            publishedDateText: publishedDateText,
            pageCount: pageCount,
        )
    }
}

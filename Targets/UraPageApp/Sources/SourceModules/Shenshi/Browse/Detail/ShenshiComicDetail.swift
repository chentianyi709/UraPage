/// 保存绅士详情页当前只读展示需要的来源专属数据。
struct ShenshiComicDetail: ComicDetailContentProviding {
    let identity: ComicIdentity
    let title: String
    let publisher: ShenshiComicPublisher?
    let category: ShenshiLatestCategory?
    let pageCount: Int?
    let commentCount: Int?
    let summary: String
    let comicTags: [ShenshiComicTag]
    let cover: ComicImageSource
    let relatedComics: [ComicListItem]

    /// 把网页唯一提供的发布者名称交给统一作者展示行。
    var authorNames: [String] {
        publisher.map { [$0.name] } ?? []
    }

    /// 网页只提供一个分类与一组标签；分类放在前面，空组由展示层跳过。
    var tagGroups: [ComicTagGroup] {
        [
            ComicTagGroup(kind: .category, values: category.map { [$0.title] } ?? []),
            ComicTagGroup(kind: .tag, values: comicTags.map(\.name)),
        ]
    }

    /// 绅士网页只提供图片数量。
    var fields: [ComicDetailField] {
        [pageCount.map(ComicDetailField.pageCount)].compactMap(\.self)
    }
}

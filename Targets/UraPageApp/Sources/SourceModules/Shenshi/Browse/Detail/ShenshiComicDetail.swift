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

    /// 向统一字段行提供绅士网页真实拥有的图片数量。
    var metadata: ComicDetailMetadata {
        ComicDetailMetadata(pageCount: pageCount)
    }
}

/// 保存哔咔详情页实际展示和导航需要的数据。
struct BikaComicDetail: ComicDetailContentProviding, Sendable {
    let identity: ComicIdentity
    let title: String
    let summary: String
    let tags: [String]
    let cover: ComicImageSource

    let contributors: [BikaComicContributor]
    let categories: [BikaComicCategory]
    let pageCount: Int
    let viewCount: Int
    let likeCount: Int
    let isLiked: Bool
    let isFinished: Bool

    /// 服务端 `updated_at` 解析后的本地日期文本；无法解析时为 `nil`。
    let updatedDateText: String?

    let chapters: [BikaComicChapter]

    /// 已完结且只有一章时直接阅读；其余情况展示章节目录入口。
    var showsChaptersButton: Bool {
        !(isFinished && chapters.count == 1)
    }

    /// 按作品作者、汉化组和上传者顺序提供统一作者行内容。
    var authorNames: [String] {
        contributors.map(\.name)
    }

    /// 分类在前、标签在后；两者都来自本源详情响应，空组由展示层跳过。
    var tagGroups: [ComicTagGroup] {
        [
            ComicTagGroup(kind: .category, values: categories.map(\.title)),
            ComicTagGroup(kind: .tag, values: tags),
        ]
    }

    /// 浏览、点赞、图片、日期与连载状态，顺序即展示顺序。
    var fields: [ComicDetailField] {
        [
            .viewCount(viewCount),
            .likeCount(likeCount),
            .pageCount(pageCount),
            updatedDateText.flatMap(ComicDetailField.updatedDate),
            .serialization(isFinished: isFinished),
        ].compactMap(\.self)
    }
}

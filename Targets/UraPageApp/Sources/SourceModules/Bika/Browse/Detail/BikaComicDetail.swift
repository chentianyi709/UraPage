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

    /// 服务端 `created_at` 解析后的本地日期文本；无法解析时为 `nil`。
    let publishedDateText: String?

    let chapters: [BikaComicChapter]

    /// 已完结且只有一章时直接阅读；其余情况展示章节目录入口。
    var showsChaptersButton: Bool {
        !(isFinished && chapters.count == 1)
    }

    /// 按作品作者、汉化组和上传者顺序提供统一作者行内容。
    var authorNames: [String] {
        contributors.map(\.name)
    }

    /// 只提供哔咔详情需要展示的统计、图片数量、创建日期和连载状态。
    var metadata: ComicDetailMetadata {
        ComicDetailMetadata(
            viewCount: viewCount,
            likeCount: likeCount,
            publishedDateText: publishedDateText,
            pageCount: pageCount,
            serializationStatus: isFinished ? .completed : .serializing,
        )
    }
}

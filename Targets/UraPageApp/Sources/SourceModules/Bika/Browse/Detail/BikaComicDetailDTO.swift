import ReerCodable

/// 解码哔咔漫画详情响应。
@Decodable
struct BikaComicDetailResponseDTO: Decodable, ReerCodableDelegate, Sendable {
    let comic: BikaComicDetailDTO
}

/// 只解码当前详情页面展示所需的漫画字段。
@Decodable
struct BikaComicDetailDTO: Decodable, ReerCodableDelegate, Sendable {
    @CodingKey("_id")
    let id: String

    @CodingKey("_creator")
    let creator: BikaComicCreatorDTO

    let title: String

    @CodingKey("description")
    @DecodingDefault("")
    let summary: String

    let thumb: BikaImageDTO
    let author: String?
    let categories: [String]

    @DecodingDefault("")
    let chineseTeam: String

    let tags: [String]
    let pagesCount: Int
    let finished: Bool
    let totalLikes: Int
    let totalViews: Int
    let isLiked: Bool

    @CodingKey("created_at")
    let createdAt: String?
}

/// 只解码详情作者组展示和上传作品导航需要的上传者字段。
@Decodable
struct BikaComicCreatorDTO: Decodable, ReerCodableDelegate, Sendable {
    @CodingKey("_id")
    let id: String

    let name: String
}

/// 解码哔咔章节分页响应。
@Decodable
struct BikaEpisodesResponseDTO: Decodable, ReerCodableDelegate, Sendable {
    let eps: BikaEpisodesPageDTO
}

/// 保存章节接口当前页、总页数和章节数组。
@Decodable
struct BikaEpisodesPageDTO: BikaPagedResponse, Decodable, ReerCodableDelegate, Sendable {
    let docs: [BikaEpisodeDTO]
    let page: Int
    let pages: Int
}

/// 解码章节标题及其可直接请求图片的顺序号。
@Decodable
struct BikaEpisodeDTO: Decodable, ReerCodableDelegate, Sendable {
    let title: String
    let order: Int
}

import ReerCodable

/// 解码哔咔章节图片分页响应。
@Decodable
struct BikaChapterContentResponseDTO: Decodable, ReerCodableDelegate, Sendable {
    let pages: BikaChapterPagesDTO
}

/// 保存章节图片当前页、总页数和页面数组。
@Decodable
struct BikaChapterPagesDTO: BikaPagedResponse, Decodable, ReerCodableDelegate, Sendable {
    let docs: [BikaChapterPageDTO]
    let total: Int
    let limit: Int
    let page: Int
    let pages: Int
}

/// 解码一张阅读页的服务端身份和图片 locator。
@Decodable
struct BikaChapterPageDTO: Decodable, ReerCodableDelegate, Sendable {
    @CodingKey("_id")
    let id: String

    let media: BikaImageDTO
}

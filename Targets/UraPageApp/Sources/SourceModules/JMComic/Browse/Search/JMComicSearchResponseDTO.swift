import ReerCodable

/// 解码禁漫 `/search` 返回的漫画总数和当前页内容。
@Decodable
struct JMComicSearchResponseDTO: Decodable, ReerCodableDelegate, Sendable {
    /// 服务端声明的结果总数；分页是否继续以原始条目数量为准。
    @FlexibleType
    let total: Int

    /// 精确作品重定向目标 ID；非空时页面直接进入该作品详情。
    @CodingKey("redirect_aid")
    @DecodingDefault("")
    @FlexibleType
    let redirectComicID: String

    let content: [JMComicListItemDTO]
}

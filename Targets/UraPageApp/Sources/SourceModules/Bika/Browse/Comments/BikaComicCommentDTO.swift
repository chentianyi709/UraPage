import ReerCodable

/// 解码哔咔漫画评论或子评论接口返回的数据区域。
@Decodable
struct BikaComicCommentsResponseDTO: Decodable, ReerCodableDelegate, Sendable {
    let comments: BikaComicCommentsPageDTO
}

/// 保存哔咔评论接口的服务端分页字段。
///
/// `page`／`pages` 是这里最可靠的分页信号：接口按页偏移，新评论插入会让后续页整体后移，
/// 用「累计条数与 total 比较」推断下一页容易多翻一页。`total` 只用来显示评论总数。
@Decodable
struct BikaComicCommentsPageDTO: Decodable, ReerCodableDelegate, Sendable {
    @DecodingDefault([])
    let docs: [BikaComicCommentDTO]

    @DecodingDefault(0)
    @FlexibleType
    let total: Int

    @DecodingDefault(1)
    @FlexibleType
    let page: Int

    @DecodingDefault(0)
    @FlexibleType
    let pages: Int
}

/// 解码顶级评论和子评论共同需要的只读展示字段。
@Decodable
struct BikaComicCommentDTO: Decodable, ReerCodableDelegate, Sendable {
    /// 评论的稳定 ID；子评论接口按它取下一页。
    @CodingKey("id")
    @DecodingDefault("")
    @FlexibleType
    let requestID: String

    @DecodingDefault("")
    let content: String

    @CodingKey("_user")
    let user: BikaComicCommentUserDTO?

    @CodingKey("created_at")
    @DecodingDefault("")
    let createdAt: String

    /// 服务端声明的回复数；两个字段取较大的一个，缺失时按 0 处理。
    @FlexibleType
    let totalComments: Int?

    @DecodingDefault(0)
    @FlexibleType
    let commentsCount: Int
}

/// 解码一条哔咔评论作者的名称和可选头像。
@Decodable
struct BikaComicCommentUserDTO: Decodable, ReerCodableDelegate, Sendable {
    @CodingKey("_id")
    @DecodingDefault("")
    @FlexibleType
    let id: String

    @DecodingDefault("")
    let name: String

    let avatar: BikaImageDTO?
}

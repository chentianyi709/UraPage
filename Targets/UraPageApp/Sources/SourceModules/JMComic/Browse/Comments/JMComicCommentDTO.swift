import ReerCodable

/// 解码禁漫 `/forum?mode=all&page={page}&aid={comicID}` 返回的评论分页。
@Decodable
struct JMComicCommentsResponseDTO: Decodable, ReerCodableDelegate {
    @CodingKey("list")
    @DecodingDefault([])
    let comments: [JMComicCommentDTO]

    @DecodingDefault(0)
    @FlexibleType
    let total: Int
}

/// 解码禁漫一条顶级评论及其随响应返回的回复。
@Decodable
struct JMComicCommentDTO: Decodable, ReerCodableDelegate {
    @CodingKey("CID")
    @DecodingDefault("")
    @FlexibleType
    let id: String

    @DecodingDefault("")
    let nickname: String

    @DecodingDefault("")
    let photo: String

    @DecodingDefault("")
    let addtime: String

    @DecodingDefault("")
    let content: String

    @CodingKey("replys")
    @DecodingDefault([])
    let replies: [JMComicCommentReplyDTO]
}

/// 解码禁漫顶级评论下展示的一条回复。
@Decodable
struct JMComicCommentReplyDTO: Decodable, ReerCodableDelegate {
    @CodingKey("CID")
    @DecodingDefault("")
    @FlexibleType
    let id: String

    @DecodingDefault("")
    let nickname: String

    @DecodingDefault("")
    let photo: String

    @DecodingDefault("")
    let addtime: String

    @DecodingDefault("")
    let content: String
}

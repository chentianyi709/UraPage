import ReerCodable

/// 解码禁漫点赞接口返回的业务结果。
@Decodable
struct JMComicLikeResponseDTO: Decodable, ReerCodableDelegate {
    /// 服务端业务状态；`success` 表示点赞成功。
    let status: String

    /// 服务端返回的展示消息。
    let msg: String
}

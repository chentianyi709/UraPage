import ReerCodable

/// 解码哔咔普通漫画卡片映射所需的最小字段。
@Decodable
struct BikaComicListItemDTO: Decodable, ReerCodableDelegate, Sendable {
    @CodingKey("_id")
    let id: String

    let title: String

    /// 作者可能缺失；缺失时副标题置空。
    @DecodingDefault("")
    let author: String

    /// 封面文件服务信息。
    let thumb: BikaImageDTO
}

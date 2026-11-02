import ReerCodable

/// 解码禁漫 `/promote_list` 返回的推广漫画总数与当前页列表。
@Decodable
struct JMComicPromotionResponseDTO: Decodable, ReerCodableDelegate, Sendable {
    /// 服务端声明的该分区漫画总数；分页是否继续以它为准。
    @FlexibleType
    let total: Int

    /// 当前页普通卡片；坏卡片由映射层逐项跳过。
    let list: [JMComicListItemDTO]
}

import ReerCodable

/// 解码哔咔随机漫画接口返回的普通卡片数组。
@Decodable
struct BikaRandomComicsResponseDTO: Decodable, ReerCodableDelegate, Sendable {
    let comics: [BikaComicListItemDTO]
}

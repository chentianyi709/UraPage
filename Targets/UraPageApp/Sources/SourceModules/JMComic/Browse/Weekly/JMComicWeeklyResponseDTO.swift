import ReerCodable

/// 解码禁漫 `/serialization` 返回的周刊漫画列表。
@Decodable
struct JMComicWeeklyResponseDTO: Decodable, ReerCodableDelegate, Sendable {
    let list: [JMComicListItemDTO]
}

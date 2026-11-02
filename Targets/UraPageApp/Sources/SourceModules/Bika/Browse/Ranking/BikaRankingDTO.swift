import ReerCodable

/// 解码漫画排行榜响应中的完整漫画数组。
@Decodable
struct BikaComicRankingResponseDTO: Decodable, ReerCodableDelegate, Sendable {
    let comics: [BikaComicListItemDTO]
}

/// 解码骑士排行榜响应中的完整用户数组。
@Decodable
struct BikaKnightRankingResponseDTO: Decodable, ReerCodableDelegate, Sendable {
    let users: [BikaKnightRankingUserDTO]
}

/// 解码骑士榜展示值映射所需的最小用户字段。
@Decodable
struct BikaKnightRankingUserDTO: Decodable, ReerCodableDelegate, Sendable {
    @CodingKey("_id")
    let id: String

    @DecodingDefault("")
    let name: String

    let avatar: BikaImageDTO?

    @DecodingDefault(0)
    let comicsUploaded: Int

    @DecodingDefault(0)
    let level: Int

    @DecodingDefault("")
    let title: String

    @DecodingDefault("")
    let slogan: String
}

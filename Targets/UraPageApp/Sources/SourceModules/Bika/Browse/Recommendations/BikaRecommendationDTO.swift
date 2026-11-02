import ReerCodable

/// 哔咔官方相关推荐接口返回的卡片数组。
@Decodable
struct BikaComicRecommendationResponseDTO: Decodable, ReerCodableDelegate, Sendable {
    let comics: [BikaComicListItemDTO]
}

/// 独立个性化服务按顺序返回的作品 ID。
struct BikaPersonalizedRecommendationResponseDTO: Decodable, Sendable {
    let code: Int
    let recommendations: [String]
}

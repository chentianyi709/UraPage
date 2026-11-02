import ReerCodable

/// 解码哔咔热门搜索接口返回的关键词数组。
@Decodable
struct BikaSearchRecommendationsDTO: Decodable, ReerCodableDelegate, Sendable {
    let keywords: [String]
}

/// 描述哔咔高级搜索的 JSON 请求体。
struct BikaAdvancedSearchRequestDTO: Encodable, Sendable {
    let keyword: String
    let sort: String

    /// 空数组时传 `nil`，表示不按分类过滤。
    let categories: [String]?
}

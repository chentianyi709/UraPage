import ReerCodable

/// 解码哔咔分类接口的有序分类数组。
@Decodable
struct BikaCategoriesResponseDTO: Decodable, ReerCodableDelegate, Sendable {
    let categories: [BikaComicCategoryDTO]
}

/// 只解码当前分类菜单和网页分类过滤所需字段。
@Decodable
struct BikaComicCategoryDTO: Decodable, ReerCodableDelegate, Sendable {
    let title: String

    /// `true` 表示只应在网页端展示的分类，原生菜单不显示。
    let isWeb: Bool?
}

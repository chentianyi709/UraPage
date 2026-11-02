import ReerCodable

/// 解码禁漫 `/categories` 返回的分类列表。
@Decodable
struct JMComicCategoriesResponseDTO: Decodable, ReerCodableDelegate, Sendable {
    let categories: [JMComicCategoryDTO]
}

/// 递归解码一个禁漫分类节点及其子分类。
@Decodable
@SnakeCase
struct JMComicCategoryDTO: Decodable, ReerCodableDelegate, Sendable {
    let name: String
    let slug: String

    @DecodingDefault([])
    let subCategories: [JMComicCategoryDTO]
}

/// 解码禁漫 `/categories/filter` 返回的筛选页。
@Decodable
@SnakeCase
struct JMComicCategoryFilterResponseDTO: Decodable, ReerCodableDelegate {
    let content: [JMComicListItemDTO]
}

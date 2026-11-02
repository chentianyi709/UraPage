/// 哔咔高级搜索的查询条件：关键词、排序与可选多分类过滤。
///
/// 作为搜索页分页执行器的查询身份：关键词或筛选变化即产生新查询，
/// 结果按新条件重新请求首屏。
struct BikaSearchQuery: Hashable, Sendable {
    /// 搜索关键词（已去掉首尾空白）。
    let keyword: String

    /// 服务端排序方式。
    let sort: BikaComicSort

    /// 限定分类；空数组表示不限分类。
    let categories: [BikaComicCategory]
}

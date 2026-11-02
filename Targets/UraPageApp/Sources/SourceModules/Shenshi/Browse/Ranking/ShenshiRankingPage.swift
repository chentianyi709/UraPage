/// 保存绅士排行榜网页声明的一级分类和可选子分类。
struct ShenshiRankingCategory: Identifiable, Hashable, Sendable {
    /// 服务端排行榜分类路径中的数字 ID。
    let id: Int

    /// 网页显示的分类名称。
    let title: String

    /// 当前一级分类包含的二级分类。
    let children: [ShenshiRankingCategory]
}

/// 保存绅士收藏排行榜的一页漫画和分页信息。
struct ShenshiRankingPage: Sendable {
    /// 按服务端排名顺序保存的漫画；分页列表不在来源层去重，坏卡片已跳过。
    let items: [ComicListItem]

    /// 当前响应对应的页码。
    let page: Int

    /// 网页分页区域声明的总页数；无法识别时为 `nil`。
    let totalPages: Int?

    /// 当前 HTML 声明的两级内容分类。
    let categories: [ShenshiRankingCategory]
}

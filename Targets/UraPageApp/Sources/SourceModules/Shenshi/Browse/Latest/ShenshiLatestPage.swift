/// 保存绅士“最近更新”页面解析出的一级分类和可选子分类。
struct ShenshiLatestCategory: Codable, Identifiable, Hashable, Sendable {
    /// 服务端分类链接中的数字 ID。
    let id: Int

    /// 转换为简体中文后的分类名称。
    let title: String

    /// 当前一级分类包含的二级分类。
    let children: [ShenshiLatestCategory]

    /// 用网页解析结果创建分类导航值。
    init(id: Int, title: String, children: [ShenshiLatestCategory]) {
        self.id = id
        self.title = title
        self.children = children
    }
}

/// 保存绅士“最新”页面的一页漫画及当前响应能识别的分页信息。
struct ShenshiLatestPage: Sendable {
    /// 当前页解析出的漫画列表。
    let items: [ComicListItem]

    /// 当前响应对应的页码。
    let page: Int

    /// 移动版分页区域声明的总页数；无法识别时为 `nil`。
    let totalPages: Int?

    /// 当前 HTML 导航区域声明的两级分类。
    let categories: [ShenshiLatestCategory]
}

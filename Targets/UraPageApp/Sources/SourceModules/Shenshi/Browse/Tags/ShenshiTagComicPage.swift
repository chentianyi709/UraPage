/// 保存绅士标签列表的一页漫画及网页声明的分页信息。
struct ShenshiTagComicPage: Sendable {
    /// 当前页解析出的漫画列表。
    let items: [ComicListItem]

    /// 当前响应对应的页码。
    let page: Int

    /// 移动版分页区域声明的总页数；无法识别时为 `nil`。
    let totalPages: Int?
}

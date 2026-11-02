/// 保存哔咔通用漫画列表的一页结果及服务端分页边界。
struct BikaComicPage: Sendable {
    let items: [ComicListItem]

    /// 服务端返回的当前页。
    let page: Int

    /// 服务端总页数。
    let totalPages: Int

    /// 创建已经完成 DTO 映射和分页校验的结果页。
    init(items: [ComicListItem], page: Int, totalPages: Int) {
        self.items = items
        self.page = page
        self.totalPages = totalPages
    }
}

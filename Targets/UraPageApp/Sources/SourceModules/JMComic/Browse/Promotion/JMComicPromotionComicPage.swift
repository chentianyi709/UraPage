/// 保存禁漫一个普通推广分区的一页漫画与服务端总数。
struct JMComicPromotionComicPage: Sendable {
    /// 当前页漫画；分页列表不在来源层去重，坏卡片已跳过。
    let comics: [ComicListItem]

    /// 服务端声明的该分区漫画总数。
    let total: Int

    /// 创建推广分页结果。
    init(comics: [ComicListItem], total: Int) {
        self.comics = comics
        self.total = total
    }
}

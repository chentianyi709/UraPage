/// 保存禁漫周刊一页漫画及服务端是否可能还有下一页。
struct JMComicWeeklyComicPage: Sendable {
    /// 当前页漫画；分页列表不在来源层去重，坏卡片已跳过。
    let comics: [ComicListItem]

    /// 是否可能还有下一页；按当前页条目数量判断。
    let hasMore: Bool

    /// 创建周刊分页结果。
    init(comics: [ComicListItem], hasMore: Bool) {
        self.comics = comics
        self.hasMore = hasMore
    }
}

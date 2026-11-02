/// 描述禁漫首页分区已经脱离服务端字符串的跳转语义。
enum JMComicHomeSectionNavigation: Sendable {
    case category(slug: String)
    case weekly
    case promotion
    case none
}

/// 保存禁漫首页一个推广分区当前展示与导航所需的内容。
struct JMComicHomeSection: Identifiable, Sendable {
    let id: String
    let title: String

    /// 当前分区漫画；静态列表不做去重，坏卡片已跳过。
    let comics: [ComicListItem]

    let navigation: JMComicHomeSectionNavigation

    /// 创建已经由禁漫 Source Target 整理完成的首页分区。
    init(id: String, title: String, comics: [ComicListItem], navigation: JMComicHomeSectionNavigation) {
        self.id = id
        self.title = title
        self.comics = comics
        self.navigation = navigation
    }
}

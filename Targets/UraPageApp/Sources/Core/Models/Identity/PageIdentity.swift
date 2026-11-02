/// 某一章节内一张漫画页的完整身份。
///
/// Reader 缓存键、离线资产与阅读进度都使用完整页面身份，
/// 不使用远程 URL、Host 或解扰参数参与身份。
struct PageIdentity: Hashable, Codable, Sendable {
    let chapter: ChapterIdentity
    let pageID: String

    /// 创建一页的完整身份；`pageID` 由来源 Mapper 提供。
    init(chapter: ChapterIdentity, pageID: String) {
        self.chapter = chapter
        self.pageID = pageID
    }
}

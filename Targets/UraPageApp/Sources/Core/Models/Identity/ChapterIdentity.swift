/// 一部漫画下某一章节的完整身份。
///
/// 章节顺序与所属关系由来源负责；Domain 只保存稳定身份。
struct ChapterIdentity: Hashable, Codable, Sendable {
    let comic: ComicIdentity
    let chapterID: String

    /// 创建某一章节的完整身份；`chapterID` 由来源 Mapper 提供。
    init(comic: ComicIdentity, chapterID: String) {
        self.comic = comic
        self.chapterID = chapterID
    }
}

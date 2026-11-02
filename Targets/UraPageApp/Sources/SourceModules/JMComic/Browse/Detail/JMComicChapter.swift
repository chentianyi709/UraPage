/// 保存禁漫详情页展示一个章节所需的来源专属数据。
struct JMComicChapter: Identifiable, Sendable {
    let identity: ChapterIdentity
    let title: String

    /// 使用完整章节身份作为列表稳定标识。
    var id: ChapterIdentity {
        identity
    }
}

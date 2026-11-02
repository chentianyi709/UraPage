/// 一部漫画在所有来源、页面与持久化边界中的完整身份。
///
/// `comicID` 是来源提供的 opaque 值，Domain 不解析其格式。
/// 当前选中来源只决定新的浏览入口，不能用来补全已存在内容的 `sourceID`。
struct ComicIdentity: Hashable, Codable, Sendable {
    let sourceID: ComicSourceID
    let comicID: String

    /// 创建一部漫画的完整身份。
    init(sourceID: ComicSourceID, comicID: String) {
        self.sourceID = sourceID
        self.comicID = comicID
    }
}

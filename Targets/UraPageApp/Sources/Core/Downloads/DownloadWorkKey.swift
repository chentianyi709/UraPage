import Foundation

/// 作品行的原始身份：来源字符串 + 作品字符串。
///
/// 与 `ComicIdentity` 的区别是**不校验来源**：重算聚合投影、清理损坏记录时，
/// 来源已不可识别的行也要能被引用。用结构体而不是拼接字符串：
/// 相等与哈希由编译器生成，不需要长度前缀来防碰撞，也不会与「章节身份」串味。
struct DownloadWorkKey: Hashable, Sendable {
    let sourceID: String
    let comicID: String

    init(sourceID: String, comicID: String) {
        self.sourceID = sourceID
        self.comicID = comicID
    }

    init(_ comic: ComicIdentity) {
        sourceID = comic.sourceID.rawValue
        comicID = comic.comicID
    }
}

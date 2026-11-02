import Foundation
import SwiftData

/// 每个作品与内容模式组合保存一条最新阅读位置和展示快照。
@Model
final class StoredReadingHistory {
    #Index<StoredReadingHistory>([\.updatedAt, \.identityKey])

    @Attribute(.unique) var identityKey: String
    var sourceID: String
    var comicID: String
    var contentModeRawValue: String
    var title: String
    var authors: [String]
    /// 封面引用（`ComicImageSource` 的 JSON 编码）；阅读记录不保存本地封面文件。
    var coverReferenceData: Data
    var chapterID: String
    var pageID: String
    var pageIndex: Int
    var chapterTitle: String
    var updatedAt: Date

    init(update: ReadingProgressUpdate, coverReferenceData: Data, updatedAt: Date) {
        let identity = update.comic.identity
        identityKey = Self.key(for: update.identity)
        sourceID = identity.sourceID.rawValue
        comicID = identity.comicID
        contentModeRawValue = update.contentMode.rawValue
        title = update.comic.title
        authors = update.comic.authors
        self.coverReferenceData = coverReferenceData
        chapterID = update.pageIdentity.chapter.chapterID
        pageID = update.pageIdentity.pageID
        pageIndex = update.pageIndex
        chapterTitle = update.chapterTitle
        self.updatedAt = updatedAt
    }

    /// 长度前缀包含来源、作品与内容模式，避免复合身份拼接碰撞。
    static func key(for identity: ReadingProgressIdentity) -> String {
        let source = identity.comic.sourceID.rawValue
        let comicID = identity.comic.comicID
        let mode = identity.contentMode.rawValue
        return "\(source.count):\(source)\(comicID.count):\(comicID)\(mode.count):\(mode)"
    }
}

import Foundation
import SwiftData

/// 一条本地收藏的书签（标签／作者／分类）。
///
/// 可展示、可排序的字段进列，来源私有身份以 payload 保存：公共层不需要认识来源结构，
/// 与下载详情把非检索字段放 blob 的处理方式一致。
@Model
final class StoredBookmark {
    #Index<StoredBookmark>([\.savedAt])

    @Attribute(.unique) var identityKey: String
    var sourceID: String
    var kind: String
    var displayName: String
    var payload: Data
    var savedAt: Date

    init(bookmark: Bookmark, savedAt: Date) {
        identityKey = bookmark.identityKey
        sourceID = bookmark.sourceID.rawValue
        kind = bookmark.kind.rawValue
        displayName = bookmark.displayName
        payload = bookmark.payload
        self.savedAt = savedAt
    }

    /// 还原成公共值；来源或维度在旧版本里已不存在时返回 `nil`。
    var bookmark: Bookmark? {
        guard let sourceID = ComicSourceID(rawValue: sourceID),
              let kind = BookmarkKind(rawValue: kind)
        else {
            return nil
        }

        return Bookmark(
            sourceID: sourceID,
            kind: kind,
            displayName: displayName,
            payload: payload,
        )
    }
}

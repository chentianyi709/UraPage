import Foundation
import SwiftData

/// 一条本地收藏的书签（分类／标签／作者／角色……）。
///
/// 可展示、可排序的字段进列，来源私有身份以 payload 保存：公共层不需要认识来源结构，
/// 与下载详情把非检索字段放 blob 的处理方式一致。
/// 书签身份 = 来源 + 维度 + 展示名，交给 `#Unique` 约束，不再存一列摘要键。
@Model
final class StoredBookmark {
    // 同一来源、同一维度、同一展示名只允许一条；重收藏覆盖 payload（与旧摘要键语义一致）。
    #Unique<StoredBookmark>([\.sourceID, \.kind, \.displayName])

    var sourceID: String

    /// 维度标识（`ComicTagKind.id`）；展示用的标题与图标由来源目录在读取时解析。
    var kind: String
    var displayName: String
    var payload: Data
    var savedAt: Date

    init(bookmark: Bookmark, savedAt: Date) {
        sourceID = bookmark.sourceID.rawValue
        kind = bookmark.kindID
        displayName = bookmark.displayName
        payload = bookmark.payload
        self.savedAt = savedAt
    }

    /// 还原成公共值；来源在旧版本里已不存在时返回 `nil`。
    ///
    /// 维度不在这里校验：来源可能已经不再提供该维度，书签仍要能展示与删除，
    /// 由展示层按「未知维度」兜底。
    var bookmark: Bookmark? {
        guard let sourceID = ComicSourceID(rawValue: sourceID) else {
            return nil
        }

        return Bookmark(
            sourceID: sourceID,
            kindID: kind,
            displayName: displayName,
            payload: payload,
        )
    }
}

import Foundation
import SwiftData

/// 每个来源、每个关键词唯一的一条搜索历史。
@Model
final class StoredSearchHistory {
    #Index<StoredSearchHistory>([\.sourceID, \.searchedAt])

    @Attribute(.unique) var identityKey: String
    var sourceID: String
    var query: String
    var searchedAt: Date

    init(sourceID: ComicSourceID, query: String, searchedAt: Date) {
        identityKey = Self.key(sourceID: sourceID, query: query)
        self.sourceID = sourceID.rawValue
        self.query = query
        self.searchedAt = searchedAt
    }

    /// 长度前缀让任意「来源 + 关键词」都不会拼接碰撞（与 `StoredReadingHistory.key` 同款）。
    static func key(sourceID: ComicSourceID, query: String) -> String {
        let source = sourceID.rawValue
        return "\(source.count):\(source)\(query.count):\(query)"
    }
}

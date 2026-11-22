import Foundation
import SwiftData

/// 每个来源、每个关键词唯一的一条搜索历史。
///
/// 每来源上限 100 条（`AppConfiguration.SearchHistory.maxEntriesPerSource`），
/// 量级小到不需要额外排序索引，只保留 `#Unique` 自带的那一个。
@Model
final class StoredSearchHistory {
    // 同一来源下同一关键词只有一条；重复搜索只更新时间。
    #Unique<StoredSearchHistory>([\.sourceID, \.query])

    var sourceID: String
    var query: String
    var searchedAt: Date

    init(sourceID: ComicSourceID, query: String, searchedAt: Date) {
        self.sourceID = sourceID.rawValue
        self.query = query
        self.searchedAt = searchedAt
    }
}

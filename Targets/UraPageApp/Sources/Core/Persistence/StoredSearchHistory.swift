import Foundation
import SwiftData

/// 每个来源、每个关键词唯一的一条搜索历史，收藏只是这条记录上的一个时间标记。
///
/// 收藏后不出现在「最近搜索」里，取消收藏按 `searchedAt` 回到最近搜索（收藏期间再次搜索会刷新该时间）；
/// 一条记录只能属于一个分区，不存在两处同时显示。
/// 未收藏的每来源上限 100 条（`AppConfiguration.SearchHistory.maxEntriesPerSource`），
/// 收藏项不参与裁剪；量级小到不需要额外排序索引，只保留 `#Unique` 自带的那一个。
@Model
final class StoredSearchHistory {
    // 同一来源下同一关键词只有一条；重复搜索只更新时间。
    #Unique<StoredSearchHistory>([\.sourceID, \.query])

    var sourceID: String
    var query: String
    var searchedAt: Date

    /// 收藏时刻；`nil` 表示未收藏，按 `searchedAt` 排在「最近搜索」里。
    var favoritedAt: Date?

    init(sourceID: ComicSourceID, query: String, searchedAt: Date, favoritedAt: Date? = nil) {
        self.sourceID = sourceID.rawValue
        self.query = query
        self.searchedAt = searchedAt
        self.favoritedAt = favoritedAt
    }
}

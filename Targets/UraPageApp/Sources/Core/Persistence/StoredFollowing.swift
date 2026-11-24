import Foundation
import SwiftData

/// 一条关注的作者。
///
/// 身份 = 来源 + 作者名，交给 `#Unique` 约束：同名不同来源是两条，删除互不影响。
/// payload 是该来源作者页的私有身份，公共层只保存、不解析。
@Model
final class StoredFollowing {
    #Unique<StoredFollowing>([\.sourceID, \.name])

    var sourceID: String
    var name: String
    var payload: Data
    var followedAt: Date

    init(following: Following, followedAt: Date) {
        sourceID = following.sourceID.rawValue
        name = following.name
        payload = following.payload
        self.followedAt = followedAt
    }

    /// 还原成公共值；来源已不存在时返回 `nil`。
    var following: Following? {
        guard let sourceID = ComicSourceID(rawValue: sourceID) else {
            return nil
        }

        return Following(sourceID: sourceID, name: name, payload: payload)
    }
}

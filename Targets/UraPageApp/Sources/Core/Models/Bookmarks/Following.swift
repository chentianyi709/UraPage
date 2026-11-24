import Foundation

/// 关注的作者身份：来源 + 作者名。
///
/// 同名不同来源视为两位作者，删除关注只影响当前来源；payload 只用于跳转，不参与身份判断。
struct FollowingIdentity: Hashable, Sendable {
    let sourceID: ComicSourceID
    let name: String
}

/// 一条关注的作者：来源 + 作者名 + 来源私有身份。
///
/// 与书签分表：关注是「订阅作者」，将来可能有自己的生命周期（新作提醒、批量管理），
/// 与只需跳转的分类／标签不同。
struct Following: Hashable, Sendable {
    let sourceID: ComicSourceID
    let name: String
    let payload: Data

    /// 稳定身份；列表 id、去重与关注态判断都用它。
    var identity: FollowingIdentity {
        FollowingIdentity(sourceID: sourceID, name: name)
    }

    /// 跳转时复用书签入口：作者维度的 `Bookmark`。
    var bookmark: Bookmark {
        Bookmark(sourceID: sourceID, kindID: ComicTagKind.author.id, displayName: name, payload: payload)
    }

    /// 用来源 typed 值创建。
    ///
    /// 参与关注的值都是只含字符串／数字的 `Codable` 结构，编码失败属于程序错误。
    init(sourceID: ComicSourceID, name: String, value: some Encodable) {
        guard let payload = try? JSONEncoder().encode(value) else {
            preconditionFailure("关注身份编码失败：\(sourceID.rawValue)/\(name)")
        }

        self.init(sourceID: sourceID, name: name, payload: payload)
    }

    /// 从作者维度的书签构造；不是作者维度时返回 `nil`。
    ///
    /// 列表页拿到的是统一的 `Bookmark`，作者页要靠它转成关注对象——转换与维度判断都收在这里。
    init?(bookmark: Bookmark) {
        guard bookmark.kindID == ComicTagKind.author.id else {
            return nil
        }

        self.init(sourceID: bookmark.sourceID, name: bookmark.displayName, payload: bookmark.payload)
    }

    /// 用已保存的 payload 还原（持久化层读取用）。
    init(sourceID: ComicSourceID, name: String, payload: Data) {
        self.sourceID = sourceID
        self.name = name
        self.payload = payload
    }
}

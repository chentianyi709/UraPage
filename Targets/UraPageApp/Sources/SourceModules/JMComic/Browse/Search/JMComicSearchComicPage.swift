/// 保存禁漫搜索的一页漫画与服务端分页信息。
///
/// 不在此层去重：页内/跨页重复由公共分页模型统一处理。
struct JMComicSearchComicPage: Sendable {
    /// 搜索结果及其搜索页专用排序元数据。
    let entries: [Entry]

    /// 不需要本地排序时使用的漫画值。
    var comics: [ComicListItem] {
        entries.map(\.comic)
    }

    /// 服务端结果总数。
    let total: Int

    /// 原始响应是否含条目；分页是否继续用它，而不是过滤后的数量。
    let hasResponseItems: Bool

    /// 精确作品重定向目标；`nil` 表示本次是普通列表结果。
    let redirectComicID: String?

    /// 创建搜索分页结果（不含去重）。
    init(
        entries: [Entry],
        total: Int,
        hasResponseItems: Bool,
        redirectComicID: String?,
    ) {
        self.entries = entries
        self.total = total
        self.hasResponseItems = hasResponseItems
        self.redirectComicID = redirectComicID
    }

    /// 搜索结果条目保留 `adddate`，供页面聚合多页后实现源码的“最旧的”本地排序。
    struct Entry: Identifiable, Sendable {
        let comic: ComicListItem
        let addedAt: String

        /// 跨页去重使用完整漫画身份，与其它列表保持一致。
        var id: ComicIdentity {
            comic.identity
        }
    }
}

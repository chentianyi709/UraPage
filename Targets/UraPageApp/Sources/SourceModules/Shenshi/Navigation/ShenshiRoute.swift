/// 绅士的 push 目标。
///
/// 详情携带漫画身份与在线／离线模式；Reader 携带打开时确定的章节快照，不携带 Services。
/// 所属来源由类型自己声明（`SourceRouteValue`），App 层不做来源判断。
nonisolated enum ShenshiRoute: SourceDetailRoute {
    /// 漫画详情。
    case detail(ComicDetailRoute)

    /// 当前详情构造的唯一在线阅读章节。
    case reader(ComicReaderInput)

    /// 详情作者链接对应的发布者投稿列表。
    case publisherComics(ShenshiComicPublisher)

    /// 详情标签链接对应的网页作品列表。
    case tagComics(ShenshiComicTag)

    /// 详情分类链接对应的更新作品列表。
    case categoryComics(ShenshiLatestCategory)

    var sourceID: ComicSourceID {
        .shenshi
    }
}

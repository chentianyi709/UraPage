/// 禁漫的 push 目标。
///
/// 详情携带漫画身份与在线／离线模式；Reader 携带打开时确定的章节快照，不携带 Services。
/// 所属来源由类型自己声明（`SourceRouteValue`），App 层不做来源判断。
nonisolated enum JMComicRoute: SourceDetailRoute {
    /// 漫画详情。
    case detail(ComicDetailRoute)

    /// 当前详情构造的在线阅读入口；包含连续章节的稳定顺序。
    case reader(ComicReaderInput)

    /// 周刊列表；内容类型与星期由页面自己选择，标题沿用首页分区的展示名称（与旧版一致）。
    case weekly(sectionTitle: String)

    /// 一个推广分区的漫画列表。
    case promotion(sectionID: String, sectionTitle: String)

    /// 详情作者行的固定关键词结果页。
    case queryComics(query: String)

    /// 详情标签对应的标签搜索结果页。
    case tagComics(String)

    var sourceID: ComicSourceID {
        .jm
    }
}

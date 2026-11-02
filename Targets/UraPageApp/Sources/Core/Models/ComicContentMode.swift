/// 指定详情与 Reader 从在线来源还是已保存的下载资产读取内容。
nonisolated enum ComicContentMode: String, Hashable, Sendable {
    /// 通过来源 Services 取得详情、章节和页面。
    case online

    /// 只从下载记录与本地资产读取；不得回退到在线请求。
    case offline
}

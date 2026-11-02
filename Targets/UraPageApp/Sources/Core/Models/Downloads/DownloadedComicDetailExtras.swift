import Foundation

/// 离线详情中不投影到作品行列的字段。
///
/// 作品行只保留列表、调度与检索直接读取的列（身份／标题／作者／标签／分类／封面引用／状态投影）；
/// 元信息、简介与来源跳转值这部分在入队时随作品行一起写入，
/// 读取时与行列、章节行组装为 `DownloadedComicDetailSnapshot`，不单独更新。
struct DownloadedComicDetailExtras: Codable, Hashable, Sendable {
    let metadata: ComicDetailMetadata
    let summary: String
    let sourceNavigationData: Data
    let showsChaptersButton: Bool

    /// 从详情页构建的展示快照取出冷字段；只有这一处转换，字段含义与来源详情一致。
    init(snapshot: DownloadedComicDetailSnapshot) {
        metadata = snapshot.metadata
        summary = snapshot.summary
        sourceNavigationData = snapshot.sourceNavigationData
        showsChaptersButton = snapshot.showsChaptersButton
    }
}

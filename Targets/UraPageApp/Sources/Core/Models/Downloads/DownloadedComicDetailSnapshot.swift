import Foundation

/// 详情页展示值：在线时由来源详情构建，离线时由作品行列与 `DownloadedComicDetailExtras` 组装。
///
/// 本类型不整体落库——下载只持久化作品行列（标题／作者／标签／分类／封面引用）与冷字段
/// `DownloadedComicDetailExtras`，离线读取在 `DownloadPersistence` 一处组装，不各自持有副本。
/// 标签组（分类、标签、角色……）由来源详情页按实际展示值提供，组数与顺序都由来源决定；
/// `sourceNavigationData` 由本源编码作者、分类、标签所需的导航值，Core 不解释这些值。
/// 相关推荐、评论与在线操作状态不进入。
struct DownloadedComicDetailSnapshot: ComicDetailContentProviding, Hashable {
    let identity: ComicIdentity
    let title: String
    let authorNames: [String]
    let metadata: ComicDetailMetadata
    let summary: String
    let tagGroups: [ComicTagGroup]
    let cover: ComicImageSource
    let sourceNavigationData: Data
    let showsChaptersButton: Bool

    init(
        detail: some ComicDetailContentProviding,
        sourceNavigationData: Data,
        showsChaptersButton: Bool,
    ) {
        identity = detail.identity
        title = detail.title
        authorNames = detail.authorNames
        metadata = detail.metadata
        summary = detail.summary
        tagGroups = detail.tagGroups
        cover = detail.cover
        self.sourceNavigationData = sourceNavigationData
        self.showsChaptersButton = showsChaptersButton
    }

    /// 由作品行列（身份／标题／作者／派生封面）与持久化冷字段组装离线详情。
    init(
        identity: ComicIdentity,
        title: String,
        authorNames: [String],
        cover: ComicImageSource,
        extras: DownloadedComicDetailExtras,
    ) {
        self.init(
            identity: identity,
            title: title,
            authorNames: authorNames,
            metadata: extras.metadata,
            summary: extras.summary,
            tagGroups: extras.tagGroups,
            cover: cover,
            sourceNavigationData: extras.sourceNavigationData,
            showsChaptersButton: extras.showsChaptersButton,
        )
    }

    private init(
        identity: ComicIdentity,
        title: String,
        authorNames: [String],
        metadata: ComicDetailMetadata,
        summary: String,
        tagGroups: [ComicTagGroup],
        cover: ComicImageSource,
        sourceNavigationData: Data,
        showsChaptersButton: Bool,
    ) {
        self.identity = identity
        self.title = title
        self.authorNames = authorNames
        self.metadata = metadata
        self.summary = summary
        self.tagGroups = tagGroups
        self.cover = cover
        self.sourceNavigationData = sourceNavigationData
        self.showsChaptersButton = showsChaptersButton
    }

    /// 详情页读取本源导航值；解码失败向上抛出。
    ///
    /// 在线与离线详情都在加载完成后调用一次。`sourceNavigationData` 由同一个进程
    /// 在入队时编码，解码失败说明写入与读取的模型不一致，属于程序错误；页面边界记录错误，
    /// 并把页面导航按“没有额外身份”处理，不在这里静默返回 `nil`。
    func sourceNavigation<Value: Decodable>(as valueType: Value.Type) throws -> Value {
        try JSONDecoder().decode(Value.self, from: sourceNavigationData)
    }
}

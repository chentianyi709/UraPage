/// 保存阅读记录离线展示所需的稳定作品信息；不包含来源 Client 或页面状态。
struct LibraryComicSnapshot: Hashable, Codable, Sendable {
    let identity: ComicIdentity
    let title: String
    let authors: [String]
    let cover: ComicImageSource

    init(identity: ComicIdentity, title: String, authors: [String], cover: ComicImageSource) {
        self.identity = identity
        self.title = title
        self.authors = authors
        self.cover = cover
    }

    init(detail: some ComicDetailContentProviding) {
        identity = detail.identity
        title = detail.title
        authors = detail.authorNames
        cover = detail.cover
    }
}

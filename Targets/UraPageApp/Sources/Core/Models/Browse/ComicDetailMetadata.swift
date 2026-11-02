/// 表示漫画详情可以统一展示的连载状态。
enum ComicSerializationStatus: Codable, Hashable, Sendable {
    /// 作品仍在连载。
    case serializing

    /// 作品已经完结。
    case completed
}

/// 保存详情页统一字段行支持的可选展示数据。
///
/// 来源只填自己真实拥有的字段，缺失保持 `nil`，公共组件据此决定是否展示。
struct ComicDetailMetadata: Codable, Hashable, Sendable {
    let viewCount: Int?
    let likeCount: Int?
    let publishedDateText: String?
    let pageCount: Int?
    let chapterCount: Int?
    let serializationStatus: ComicSerializationStatus?

    /// 创建一组由具体漫画源提供、缺失时保持为空的详情字段。
    init(
        viewCount: Int? = nil,
        likeCount: Int? = nil,
        publishedDateText: String? = nil,
        pageCount: Int? = nil,
        chapterCount: Int? = nil,
        serializationStatus: ComicSerializationStatus? = nil,
    ) {
        self.viewCount = viewCount
        self.likeCount = likeCount
        self.publishedDateText = publishedDateText
        self.pageCount = pageCount
        self.chapterCount = chapterCount
        self.serializationStatus = serializationStatus
    }
}

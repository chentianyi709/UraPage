import ReerCodable

/// 解码禁漫 `/album` 当前详情展示所需的字段。
@Decodable
@SnakeCase
struct JMComicDetailDTO: Decodable, ReerCodableDelegate {
    @FlexibleType
    let id: String

    let name: String

    @DecodingDefault([])
    let author: [String]

    @DecodingDefault(0)
    @FlexibleType
    let addtime: Int

    @DecodingDefault("")
    let description: String

    @DecodingDefault([])
    let tags: [String]

    @DecodingDefault([])
    let series: [JMComicChapterDTO]

    @DecodingDefault(0)
    @FlexibleType
    let totalViews: Int

    @DecodingDefault(0)
    @FlexibleType
    let likes: Int

    @DecodingDefault(false)
    let liked: Bool

    @DecodingDefault(0)
    @FlexibleType
    let commentTotal: Int

    /// 服务端返回的图片总数量；详情接口不保证返回，缺失时保持 `nil`（界面不显示该字段）。
    @FlexibleType
    let totalPhotos: Int?

    @DecodingDefault([])
    let relatedList: [JMComicRelatedDTO]
}

/// 解码禁漫详情接口返回的单个章节字段。
@Decodable
struct JMComicChapterDTO: Decodable, ReerCodableDelegate {
    /// 缺少章节 ID 时先解码为空字符串，再由 Mapper 只过滤该章节，避免丢失整个章节列表。
    @DecodingDefault("")
    @FlexibleType
    let id: String

    @DecodingDefault(0)
    @FlexibleType
    let sort: Int

    @DecodingDefault("")
    let name: String
}

/// 解码详情接口相关推荐卡片的来源字段。
@Decodable
struct JMComicRelatedDTO: Decodable, ReerCodableDelegate {
    @FlexibleType
    let id: String

    @DecodingDefault("")
    let name: String

    @DecodingDefault("")
    let author: String

    @DecodingDefault("")
    let image: String
}

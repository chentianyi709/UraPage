import ReerCodable

/// 解码禁漫 `/comic_read` 返回的章节页面数据。
@Decodable
@SnakeCase
struct JMComicChapterContentDTO: Decodable, ReerCodableDelegate {
    /// 服务端返回的漫画 aid，用于计算当前图片的解扰切片数。
    @FlexibleType
    let id: String

    /// 判断当前章节是否需要图片解扰的阈值。
    @CodingKey("scramble_id")
    @FlexibleType
    let scrambleID: String

    /// 服务端返回的章节标题，只用作章节快照。
    @DecodingDefault("")
    let name: String

    /// 服务端返回的有序图片项。
    @DecodingDefault([])
    let images: [JMComicChapterPageDTO]
}

/// 解码 `/comic_read.images` 中的一张原始页面。
@Decodable
struct JMComicChapterPageDTO: Decodable, ReerCodableDelegate {
    /// 服务端页序号，用于排序和建立稳定 PageIdentity。
    @FlexibleType
    let page: Int

    /// 来源返回的图片定位值，只在 Source Target 内解析。
    let image: String
}

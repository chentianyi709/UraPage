import ReerCodable

/// 解码禁漫 `/promote` 返回的首页分区及其漫画列表。
@Decodable
struct JMComicHomeSectionDTO: Decodable, ReerCodableDelegate {
    @FlexibleType
    let id: String

    let title: String

    /// 服务端分区类型，用于区分分类/周刊/推广等内容语义。
    let type: String

    /// 分类分区请求使用的 slug；非分类分区为空。
    @DecodingDefault("")
    let slug: String

    let content: [JMComicListItemDTO]
}

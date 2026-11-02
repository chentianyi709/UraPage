import ReerCodable

/// 解码禁漫普通漫画列表接口共同返回的卡片字段。
@Decodable
struct JMComicListItemDTO: Decodable, ReerCodableDelegate {
    /// 服务端漫画 ID；可能以数字或字符串返回，故用 FlexibleType 兼容。
    @FlexibleType
    let id: String

    let name: String
    let author: String

    /// 封面地址；缺失时置空，由映射层按规则生成默认封面。
    @DecodingDefault("")
    let image: String

    /// 更新时间；既用于默认封面的内容版本，也可能参与展示。
    @CodingKey("update_at")
    @DecodingDefault(0)
    @FlexibleType
    let updatedAt: Int

    /// 搜索页“最旧的”选项使用的发布时间；其它列表接口未返回时为空。
    @CodingKey("adddate")
    @DecodingDefault("")
    @FlexibleType
    let addedAt: String
}

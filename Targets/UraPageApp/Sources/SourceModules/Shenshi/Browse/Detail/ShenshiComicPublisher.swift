/// 表示绅士详情页中拥有投稿列表的发布者。
struct ShenshiComicPublisher: Codable, Hashable, Sendable {
    /// 网页作者链接中的数字用户 ID。
    let id: String

    /// 详情作者行与投稿列表标题共用的名称。
    let name: String

    /// 用网页解析结果创建发布者导航值。
    init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

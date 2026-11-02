/// 描述哔咔漫画列表可以选择的一个服务端分类。
struct BikaComicCategory: Codable, Identifiable, Hashable, Sendable {
    /// 分类接口和漫画列表接口共同使用原始标题作为选择身份。
    var id: String {
        title
    }

    let title: String

    /// 用来源 DTO 声明的分类名创建服务端分类值。
    init(title: String) {
        self.title = title
    }
}

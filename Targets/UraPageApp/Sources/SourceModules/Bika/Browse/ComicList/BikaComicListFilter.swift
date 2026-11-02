/// 描述哔咔通用漫画结果页当前使用的服务端筛选条件。
enum BikaComicListFilter: Hashable, Sendable {
    /// 按服务端分类查询漫画。
    case category(BikaComicCategory)

    /// 按详情返回的标签名称查询漫画。
    case tag(String)

    /// 按作者、汉化组或上传者查询漫画。
    case contributor(BikaComicContributor)

    /// 返回导航标题使用的筛选名称。
    var title: String {
        switch self {
        case let .category(category):
            category.title
        case let .tag(name):
            name
        case let .contributor(contributor):
            contributor.name
        }
    }

    /// 返回 `GET comics` 使用的唯一筛选参数。
    var requestParameter: (key: String, value: String) {
        switch self {
        case let .category(category):
            ("c", category.title)
        case let .tag(name):
            ("t", name)
        case let .contributor(.author(name)):
            ("a", name)
        case let .contributor(.chineseTeam(name)):
            ("ct", name)
        case let .contributor(.uploader(id, _)):
            ("ca", id)
        }
    }
}

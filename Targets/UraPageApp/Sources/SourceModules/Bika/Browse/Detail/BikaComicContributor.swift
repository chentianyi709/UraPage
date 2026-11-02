/// 表示哔咔详情作者组中可直接查询作品的贡献者。
enum BikaComicContributor: Codable, Hashable, Sendable {
    /// 使用作者名称查询作品。
    case author(name: String)

    /// 使用汉化组名称查询作品。
    case chineseTeam(name: String)

    /// 使用上传者 ID 查询作品，名称只用于展示。
    case uploader(id: String, name: String)

    /// 返回详情作者行和作品列表共用的名称。
    var name: String {
        switch self {
        case let .author(name), let .chineseTeam(name), let .uploader(_, name):
            name
        }
    }
}

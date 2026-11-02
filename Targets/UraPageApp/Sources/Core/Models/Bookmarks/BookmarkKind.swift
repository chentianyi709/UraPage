/// 可收藏的检索维度：作者、分类、标签。
///
/// 三类共用同一套收藏与跳转流程，只在分组标题上区分；具体身份由来源私有
/// payload 承载（见 `Bookmark`），这里不掺任何来源字段。
enum BookmarkKind: String, Codable, Sendable, CaseIterable, Identifiable {
    case author
    case category
    case tag

    var id: String {
        rawValue
    }

    /// 分组标题与无障碍文案使用的维度名称。
    var title: String {
        switch self {
        case .author: "作者"
        case .category: "分类"
        case .tag: "标签"
        }
    }
}

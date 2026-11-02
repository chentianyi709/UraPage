/// 定义哔咔漫画列表接口支持的固定排序方式。
enum BikaComicSort: Hashable, CaseIterable, Identifiable, Sendable {
    case latest
    case oldest
    case mostLiked
    case mostViewed

    var id: Self {
        self
    }

    /// 返回结果页排序菜单展示的名称。
    var displayTitle: String {
        switch self {
        case .latest:
            "新到旧"
        case .oldest:
            "旧到新"
        case .mostLiked:
            "最多喜欢"
        case .mostViewed:
            "最多观看"
        }
    }

    /// 返回 `GET comics` 的 `s` 查询值。
    var requestValue: String {
        switch self {
        case .latest:
            "dd"
        case .oldest:
            "da"
        case .mostLiked:
            "ld"
        case .mostViewed:
            "vd"
        }
    }
}

import Foundation

/// 定义禁漫周刊接口支持的内容类型。
enum JMComicWeeklyContentType: String, CaseIterable, Identifiable, Sendable {
    case all
    case manga
    case hanman

    var id: String {
        rawValue
    }

    /// 返回内容类型菜单使用的用户可读名称。
    var displayTitle: String {
        switch self {
        case .all:
            "全部"
        case .manga:
            "同人"
        case .hanman:
            "韩漫"
        }
    }
}

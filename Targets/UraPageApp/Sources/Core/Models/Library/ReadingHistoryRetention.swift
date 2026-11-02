/// 阅读历史的保留时长档位；到期记录会在启动、打开历史页或缩短周期时清理。
///
/// `rawValue` 是保留天数，`unlimited` 用 `0` 表示不限制；持久化的就是这个 raw value。
/// 仅定义阅读历史的保留周期，不限制记录数量。
nonisolated enum ReadingHistoryRetention: Int, CaseIterable, Sendable {
    case days30 = 30
    case days90 = 90
    case days180 = 180
    case oneYear = 365
    case twoYears = 730
    case threeYears = 1095
    case unlimited = 0

    /// 首次使用且尚未设置保留周期时使用 1 年。
    static let defaultValue: ReadingHistoryRetention = .oneYear

    /// 保留天数；`nil` 表示不限制。
    var dayCount: Int? {
        self == .unlimited ? nil : rawValue
    }

    var title: String {
        switch self {
        case .days30: "30 天"
        case .days90: "90 天"
        case .days180: "180 天"
        case .oneYear: "1 年"
        case .twoYears: "2 年"
        case .threeYears: "3 年"
        case .unlimited: "不限制"
        }
    }
}

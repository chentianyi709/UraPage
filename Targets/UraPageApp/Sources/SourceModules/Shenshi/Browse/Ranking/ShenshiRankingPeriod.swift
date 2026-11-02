/// 描述绅士收藏排行榜支持的固定统计周期。
enum ShenshiRankingPeriod: Hashable, CaseIterable, Sendable {
    /// 当日收藏排行。
    case daily

    /// 本周收藏排行，也是网页默认周期。
    case weekly

    /// 本月收藏排行。
    case monthly

    /// 本年收藏排行。
    case yearly

    /// 返回排行榜筛选菜单使用的简体标题。
    var title: String {
        switch self {
        case .daily:
            "今日"
        case .weekly:
            "本周"
        case .monthly:
            "本月"
        case .yearly:
            "今年"
        }
    }

    /// 返回网页路径要求的周期值。
    var requestValue: String {
        switch self {
        case .daily:
            "day"
        case .weekly:
            "week"
        case .monthly:
            "month"
        case .yearly:
            "year"
        }
    }

    /// 用菜单选择 id（网页周期值）还原周期；无法识别时返回 `nil`。
    init?(requestValue: String) {
        guard let period = Self.allCases.first(where: { $0.requestValue == requestValue }) else {
            return nil
        }

        self = period
    }
}

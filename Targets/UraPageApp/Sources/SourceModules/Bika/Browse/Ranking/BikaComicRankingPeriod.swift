/// 描述哔咔漫画排行榜支持的固定统计周期。
enum BikaComicRankingPeriod: Hashable, CaseIterable, Identifiable, Sendable {
    /// 最近二十四小时的漫画排行。
    case daily

    /// 最近七天的漫画排行。
    case weekly

    /// 最近三十天的漫画排行。
    case monthly

    /// 使用周期自身作为列表的稳定标识（供标签切换与分页组件使用）。
    var id: Self {
        self
    }

    /// 返回排行榜页面展示的周期标题。
    var title: String {
        switch self {
        case .daily:
            "日榜"
        case .weekly:
            "周榜"
        case .monthly:
            "月榜"
        }
    }

    /// 返回哔咔排行榜接口要求的 `tt` 查询值。
    var requestValue: String {
        switch self {
        case .daily:
            "H24"
        case .weekly:
            "D7"
        case .monthly:
            "D30"
        }
    }
}

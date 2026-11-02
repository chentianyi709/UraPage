/// 禁漫搜索页的类型筛选（接口参数 `search_type`）。
///
/// 取值来自 2.1.9 源码 `assets/JsonData.ts` 的 `SearchTypeData`；展示名用简体中文。
enum JMComicSearchType: String, CaseIterable, Identifiable, Sendable {
    /// 站内搜索。
    case site

    /// 作品。
    case work

    /// 作者。
    case author

    /// 标签。
    case tag

    /// 角色。
    case character

    var id: String {
        rawValue
    }

    /// 返回筛选菜单展示的名称。
    var displayTitle: String {
        switch self {
        case .site:
            "站内搜索"
        case .work:
            "作品"
        case .author:
            "作者"
        case .tag:
            "标签"
        case .character:
            "角色"
        }
    }
}

/// 禁漫搜索页的年月筛选（接口参数 `y`／`m`，两者都可以为空）。
///
/// 年份可选范围自 2017 年起（源码 `Search.tsx` 的 `yearOptions`），月份 1…12；
/// 都为空时请求不下发 `y`／`m`。
struct JMComicSearchDateFilter: Equatable, Sendable {
    /// 最早可选年份（源码固定从 2017 开始）。
    static let earliestYear = 2017

    /// 可选月份。
    static let selectableMonths = Array(1 ... 12)

    /// 年份；`nil` 表示不限。
    var year: Int?

    /// 月份；`nil` 表示不限。
    var month: Int?

    /// 可选年份（今年到最早年份，降序）；早于 2017 时自然返回空数组。
    static func selectableYears(currentYear: Int) -> [Int] {
        Array(stride(from: currentYear, through: earliestYear, by: -1))
    }

    /// 接口参数 `y`；`nil` 表示不下发。
    var requestYear: String? {
        year.map(String.init)
    }

    /// 接口参数 `m`；`nil` 表示不下发。
    var requestMonth: String? {
        month.map(String.init)
    }
}

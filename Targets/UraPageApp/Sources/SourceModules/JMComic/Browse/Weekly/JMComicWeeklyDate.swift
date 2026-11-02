import Foundation

/// 定义禁漫周刊接口支持的星期与完结筛选值。
enum JMComicWeeklyDate: Int, CaseIterable, Identifiable, Sendable {
    case monday = 1
    case tuesday = 2
    case wednesday = 3
    case thursday = 4
    case friday = 5
    case saturday = 6
    case sunday = 7
    case completed = 0

    var id: Int {
        rawValue
    }

    /// 返回日期菜单与页面标题使用的用户可读名称。
    var displayTitle: String {
        switch self {
        case .monday:
            "周一"
        case .tuesday:
            "周二"
        case .wednesday:
            "周三"
        case .thursday:
            "周四"
        case .friday:
            "周五"
        case .saturday:
            "周六"
        case .sunday:
            "周日"
        case .completed:
            "完结"
        }
    }

    /// 按设备当前日历返回周一至周日的默认筛选值。
    static var currentWeekday: JMComicWeeklyDate {
        let weekday = Calendar.current.component(.weekday, from: .now)

        switch weekday {
        case 1:
            return .sunday
        case 2:
            return .monday
        case 3:
            return .tuesday
        case 4:
            return .wednesday
        case 5:
            return .thursday
        case 6:
            return .friday
        case 7:
            return .saturday
        default:
            // Calendar 的 weekday 固定为 1...7；越界说明运行环境异常，
            // 直接暴露而不是静默返回一个错误日期。
            preconditionFailure("非法的 weekday：\(weekday)")
        }
    }
}

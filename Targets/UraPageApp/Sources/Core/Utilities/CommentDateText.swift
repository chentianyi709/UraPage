import Foundation

/// 把评论时间折成「今天／昨天／N 天前／M 月 D 日」这类相对文案。
///
/// 三个来源的原始时间格式不同：禁漫是 `MMM dd, yyyy`、哔咔是 ISO 8601、绅士的网页本身
/// 就是格式化好的文本。解析留在各自 mapper，这里只统一折算规则，保证列表里的说法一致。
///
/// 评论里「多久以前」比具体时刻更有用，所以一年以内省掉年份；超过一年才写全，
/// 免得近期的评论都被年份占掉一截宽度。
enum CommentDateText {
    /// 相对文案。
    ///
    /// - Parameters:
    ///   - date: 评论时间。
    ///   - now: 计算基准；默认当前时刻。
    ///   - calendar: 用户日历，决定「一天」的边界与是否同一年。
    static func formatted(
        _ date: Date,
        now: Date = Date(),
        calendar: Calendar = .current,
    ) -> String {
        let startOfDate = calendar.startOfDay(for: date)
        let startOfToday = calendar.startOfDay(for: now)
        // 跨夏令时或日历异常时取不到天数差，按「今天」处理，避免退回空白文案。
        let dayDifference = calendar.dateComponents(
            [.day],
            from: startOfDate,
            to: startOfToday,
        )
        .day ?? 0

        switch dayDifference {
        case 0:
            return "今天"
        case 1:
            return "昨天"
        case 2 ... 7:
            return "\(dayDifference)天前"
        default:
            return absoluteText(for: date, now: now, calendar: calendar)
        }
    }

    /// 超出「N 天前」的日期：同年省掉年份，跨年写全。
    private static func absoluteText(
        for date: Date,
        now: Date,
        calendar: Calendar,
    ) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = components.year,
              let month = components.month,
              let day = components.day
        else {
            return ""
        }

        return year == calendar.component(.year, from: now)
            ? "\(month)月\(day)日"
            : "\(year)年\(month)月\(day)日"
    }
}

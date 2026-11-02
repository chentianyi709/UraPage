import SwiftUI

/// 禁漫封面左上角的「更新」标记。
///
/// **这是禁漫自己的展示规则**，所以判定与样式都留在本源模块：公共卡片只提供
/// `ComicCardView` 的 `coverOverlay` 叠层入口，不认识「更新」这个概念，
/// 也不需要任何全局开关（叠层由页面决定，页面不认识就什么都不画）。
///
/// 判定与旧版 `jm_v1` 的 `Int.isUpdatedWithin3Days` 一致：按自然日比较（忽略时分秒），
/// 更新时间与今天相差不超过 3 天就显示；未来时间戳同样算作最近更新。
struct JMComicUpdateTag: View {
    /// 最近更新的自然日窗口。
    private static let recentDayWindow = 3

    var body: some View {
        Text("更新")
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(Color.textOnPrimary)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color.brandPrimary)
            .clipShape(Capsule())
            .padding([.top, .leading], 6)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// 更新时间是否落在最近更新的自然日窗口内；来源没有给出时间时（`nil`）不显示。
    static func isRecent(_ updatedAt: Date?) -> Bool {
        guard let updatedAt else {
            return false
        }

        let calendar = Calendar.current
        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: updatedAt),
            to: calendar.startOfDay(for: Date()),
        )
        .day ?? 0

        return days <= recentDayWindow
    }
}

/// 卡片封面叠层：最近更新时显示「更新」，否则什么都不画。
///
/// 禁漫的浏览页面把它作为 `coverOverlay` 交给公共列表，公共层原样放在封面之上。
struct JMComicUpdateOverlay: View {
    let item: ComicListItem

    var body: some View {
        if JMComicUpdateTag.isRecent(item.updatedAt) {
            JMComicUpdateTag()
        }
    }
}

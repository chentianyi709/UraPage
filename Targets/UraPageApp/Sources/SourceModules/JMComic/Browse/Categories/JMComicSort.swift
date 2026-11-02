/// 禁漫**分类页**的排序参数（对应源码 `assets/JsonData.ts` 的 `CatSortData`，
/// 与接口文档 §5.3 `/categories/filter` 的 `o` 取值一致）：
/// `""`＝最新、`tf`＝最多爱心、`mv`＝总排名、`mv_m`＝月排名、`mp_w`＝周排名；
/// 源码里还有一行被注释掉的「日排名」（key `mp_t`），未启用。
/// 声明顺序即菜单展示顺序，第一项是默认排序。搜索页另有独立的 `JMComicSearchSort`。
enum JMComicSort: String, CaseIterable, Identifiable, Sendable {
    /// 最新；服务端用空字符串表示。
    case latest = ""

    /// 最多爱心。
    case mostHearts = "tf"

    /// 总排名。
    case totalRanking = "mv"

    /// 月排名。
    case monthlyRanking = "mv_m"

    /// 周排名。
    case weeklyRanking = "mp_w"

    var id: String {
        rawValue
    }

    /// 返回排序按钮统一展示的用户可读名称。
    var displayTitle: String {
        switch self {
        case .latest:
            "最新"
        case .mostHearts:
            "最多爱心"
        case .totalRanking:
            "总排名"
        case .monthlyRanking:
            "月排名"
        case .weeklyRanking:
            "周排名"
        }
    }
}

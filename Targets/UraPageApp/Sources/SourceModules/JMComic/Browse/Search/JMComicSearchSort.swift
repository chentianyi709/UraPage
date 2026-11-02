/// 禁漫搜索页的排序参数（对应源码 `assets/JsonData.ts` 的 `SearchSortData`）：
/// `""`＝最新、`mv`＝最多点阅、`mp`＝最多图片、`tf`＝最多爱心、`old`＝最旧的。
///
/// 与分类页是两套取值；`old` 仍会把 `o=old` 交给服务端，但排序由客户端按 `adddate` 升序完成
/// （源码 `Search.tsx` 里的 `isLocalOldest` 分支），因此这里用 `isLocalOldest` 标出。
enum JMComicSearchSort: String, CaseIterable, Identifiable, Sendable {
    /// 最新；服务端用空字符串表示。
    case latest = ""

    /// 最多点阅。
    case mostViews = "mv"

    /// 最多图片。
    case mostImages = "mp"

    /// 最多爱心。
    case mostHearts = "tf"

    /// 最旧的；服务端仍收到该值，排序在客户端按发布时间升序完成。
    case oldest = "old"

    var id: String {
        rawValue
    }

    /// 是否由客户端本地排序（源码 `isLocalOldest`）。
    ///
    /// 搜索页按它分流：服务端仍收到 `o=old`，页面聚合各页 `JMComicSearchComicPage.Entry`
    /// 后按 `addedAt` 升序重排（源码 `Search.tsx` 的 `adddate` 分支）。
    var isLocalOldest: Bool {
        self == .oldest
    }

    /// 返回排序按钮统一展示的用户可读名称。
    var displayTitle: String {
        switch self {
        case .latest:
            "最新"
        case .mostViews:
            "最多点阅"
        case .mostImages:
            "最多图片"
        case .mostHearts:
            "最多爱心"
        case .oldest:
            "最旧的"
        }
    }
}

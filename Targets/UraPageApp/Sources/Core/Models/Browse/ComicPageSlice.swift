/// 来源声明的下一页规则；公共分页模型只执行这几种已存在的策略。
///
/// 来源使用原始响应得出这些结论，不能交给 UI 看清洗后的 `items.count` 猜测。
enum ComicPageContinuation<Cursor: Sendable>: Sendable {
    /// 没有下一页。
    case end

    /// 使用来源可靠的 page/pages 或 next cursor 继续。
    case next(Cursor)

    /// 本页必须产生新条目才继续；`total` 存在时累计有效数量还要小于它。
    case whileMakingProgress(cursor: Cursor, total: Int?)
}

/// 一页漫画展示值与下一页规则；不含 route、Task 或 UI 错误文案。
///
/// 与 `PageSlice` 完全同形，只固定条目为 `ComicListItem`；保留名称供漫画列表的
/// 描述与分页 API 使用，不额外维护一份结构体。
typealias ComicPageSlice<Cursor: Sendable> = PageSlice<ComicListItem, Cursor>

/// 任意身份的通用分页切片；供需要保留来源额外字段的分页页面使用。
///
/// `ComicPageSlice` 是它在 `ComicListItem` 上的专用形状；`PagingModel` 只依赖
/// `Item.ID` 做跨页去重，不解释条目的业务字段。
struct PageSlice<Item: Identifiable & Sendable, Cursor: Sendable>: Sendable {
    let items: [Item]
    let continuation: ComicPageContinuation<Cursor>

    init(items: [Item], continuation: ComicPageContinuation<Cursor>) {
        self.items = items
        self.continuation = continuation
    }
}

extension ComicPageContinuation {
    /// 无总数的常用规则（例如搜索页）：空页或本页没有新增条目时由分页模型停止。
    static func whileMakingProgress(cursor: Cursor) -> Self {
        .whileMakingProgress(cursor: cursor, total: nil)
    }

    /// 来源标志驱动的续接：`hasMore` 为真时按 cursor 继续，否则结束。
    static func whileMakingProgress(cursor: Cursor, hasMore: Bool) -> Self {
        hasMore ? .whileMakingProgress(cursor: cursor, total: nil) : .end
    }
}

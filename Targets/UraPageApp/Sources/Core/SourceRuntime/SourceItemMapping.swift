import Foundation

/// 来源列表的逐项映射策略：单项不可用由 Mapper 返回 `nil` 表达，不通过“抛错再吞错”实现（§11.3）。
///
/// 只跳过明确的“该项不可用”并记录跳过数量；响应级错误（分页错位、解码失败、网络失败）
/// 仍在各有来源错误边界抛出，不会被这里吞掉。末页判断继续使用响应原始条数，与此无关。
enum SourceItemMapping {
    /// 逐项映射并跳过 `nil`；仅在确有跳过时输出一条 Debug 日志，便于发现协议改版。
    static func compactMap<Element, Item>(
        _ elements: [Element],
        category: String,
        transform: (Element) -> Item?,
    ) -> [Item] {
        var items: [Item] = []
        items.reserveCapacity(elements.count)
        var skipped = 0

        for element in elements {
            if let item = transform(element) {
                items.append(item)
            } else {
                skipped += 1
            }
        }

        if skipped > 0 {
            AppLogger.debug("跳过不可用条目 \(skipped)/\(elements.count)", category: category)
        }

        return items
    }
}

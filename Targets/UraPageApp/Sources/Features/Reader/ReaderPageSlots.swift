
/// 在进入 MainActor 前建立完整逻辑槽位；未获取的分页不需要伪造服务器页面身份。
nonisolated enum ReaderPageSlots {
    @concurrent
    static func prepare(
        content: SourceChapterContent,
    ) async throws -> [ReaderPageSlot] {
        try Task.checkCancellation()
        let resolved = Dictionary(uniqueKeysWithValues: content.pages.map { ($0.index, $0) })
        let slots = (0 ..< content.totalPageCount).map { index in
            ReaderPageSlot(
                identity: ReaderPagePosition(chapter: content.identity, index: index),
                resolvedPage: resolved[index],
            )
        }
        try Task.checkCancellation()
        return slots
    }

    /// 定位只读取已建立的槽位；菜单切章总是从首页开始，继续阅读使用正式记录。
    @concurrent
    static func initialPage(
        in slots: [ReaderPageSlot],
        content: SourceChapterContent,
        startPosition: ReaderStartPosition?,
    ) async -> ReaderPageSlot? {
        // 完整清单可按服务器身份定位；分页未到达的位置直接使用正式记录的章内序号。
        let matchingIndex = startPosition.flatMap { position in
            content.pages.first(where: { $0.identity == position.pageIdentity })?.index
        }
        let index = matchingIndex ?? startPosition?.pageIndex ?? 0
        return slots.indices.contains(index) ? slots[index] : slots.first
    }
}

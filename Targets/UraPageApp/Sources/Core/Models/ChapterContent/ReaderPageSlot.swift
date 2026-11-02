/// 阅读画布中的逻辑位置，不充当服务器 PageIdentity，也不用于持久化或图片缓存。
struct ReaderPagePosition: Hashable, Sendable {
    let chapter: ChapterIdentity
    let index: Int
}

/// 总页数确定后即可建立槽位；清单尚未返回时仍能显示真实序号并定位。
struct ReaderPageSlot: Identifiable, Equatable, Sendable {
    let identity: ReaderPagePosition
    var resolvedPage: ComicPage?

    var id: ReaderPagePosition {
        identity
    }

    var index: Int {
        identity.index
    }
}

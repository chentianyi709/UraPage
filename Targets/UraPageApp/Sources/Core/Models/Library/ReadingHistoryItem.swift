import Foundation

/// 阅读进度的完整身份：同一作品的在线与离线阅读互不覆盖。
struct ReadingProgressIdentity: Hashable, Sendable {
    let comic: ComicIdentity
    let contentMode: ComicContentMode
}

/// 一部作品在指定内容模式下最近一次已保存的精确页面位置。
struct ReadingProgress: Hashable, Sendable {
    let pageIdentity: PageIdentity
    let pageIndex: Int
    let chapterTitle: String
    let contentMode: ComicContentMode
    let updatedAt: Date

    var identity: ReadingProgressIdentity {
        ReadingProgressIdentity(comic: pageIdentity.chapter.comic, contentMode: contentMode)
    }
}

/// Reader 提交的一次不可变阅读位置、内容模式与作品展示快照。
struct ReadingProgressUpdate: Equatable, Sendable {
    let comic: LibraryComicSnapshot
    let contentMode: ComicContentMode
    let pageIdentity: PageIdentity
    let pageIndex: Int
    let chapterTitle: String

    var identity: ReadingProgressIdentity {
        ReadingProgressIdentity(comic: comic.identity, contentMode: contentMode)
    }
}

/// 书架展示值，不把 SwiftData 模型带到 UI。
struct ReadingHistoryItem: Identifiable, Hashable, Sendable {
    let comic: LibraryComicSnapshot
    let progress: ReadingProgress

    var id: ReadingProgressIdentity {
        progress.identity
    }
}

/// 阅读记录按更新时间倒序分页的稳定边界。
struct ReadingHistoryCursor: Equatable, Sendable {
    let revision: UInt64
    let updatedAt: Date
    let identityKey: String
}

struct ReadingHistoryPage: Sendable {
    let items: [ReadingHistoryItem]
    let nextCursor: ReadingHistoryCursor?
}

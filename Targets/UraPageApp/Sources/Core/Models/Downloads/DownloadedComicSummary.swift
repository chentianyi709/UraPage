import Foundation

/// 一部作品的下载聚合快照，供书架「下载记录」展示：封面、标题与整体状态。
///
/// 值为持久化投影（`StoredDownloadedComic`）或运行时快照（正在下载的作品）：
/// 状态与章节计数在作品行持久化并由 `DownloadPersistence` 按章节行维护；
/// 进度是运行时的单位计数（章节信息＋分页＋页图片；封面不计入，只参与作品完成判定），
/// 未运行时为 `nil`，此时界面只按状态展示。
struct DownloadedComicSummary: Identifiable, Hashable, Sendable {
    /// 当前正在处理的部分的进度形态。
    enum Progress: Hashable, Sendable {
        /// 正在打开章节、还没有分母。
        case preparing

        /// 已打开章节，正在核对已下载内容与待下载页。
        case checking

        /// 已确定的单位比例（0…1）：单章与多章口径一致，只反映当前章节的单位进度，封面不计入。
        case units(Double)
    }

    let identity: ComicIdentity
    let title: String
    let authors: [String]
    let cover: ComicImageSource

    /// 作品级聚合状态（见 `aggregateState(_:coverState:)`）。
    let state: DownloadState

    /// 已完成章节数与已选章节总数；多章作品用它显示「已下载/总数」。
    let completedChapterCount: Int
    let chapterCount: Int

    /// 运行中的进度；`nil` 表示没有正在处理的章节（只剩封面，或未在运行）。
    let progress: Progress?

    let updatedAt: Date

    var id: ComicIdentity {
        identity
    }

    func replacingState(_ state: DownloadState) -> Self {
        Self(
            identity: identity,
            title: title,
            authors: authors,
            cover: cover,
            state: state,
            completedChapterCount: completedChapterCount,
            chapterCount: chapterCount,
            progress: progress,
            updatedAt: updatedAt,
        )
    }

    /// 从各章节状态和封面状态聚合作品级状态。
    ///
    /// 章节全部还在排队（例如在等每来源作品名额）时一律按「等待中」展示：封面是独立并行处理的，
    /// 不改变作品自身的排队状态。其余情况：全部完成 → `completed`；否则优先反映正在进行的部分
    /// （downloading → queued），再显示暂停，最后是 `failed`，保证「部分成功」也能被重试。
    static func aggregateState(_ chapterStates: [DownloadState], coverState: DownloadState) -> DownloadState {
        guard !chapterStates.isEmpty else { return .queued }

        if chapterStates.allSatisfy({ $0 == .queued }) {
            return .queued
        }

        return aggregateState(chapterStates + [coverState])
    }

    static func aggregateState(_ states: [DownloadState]) -> DownloadState {
        guard !states.isEmpty else {
            return .queued
        }

        if states.allSatisfy({ $0 == .completed }) {
            return .completed
        }
        if states.contains(.downloading) {
            return .downloading
        }
        if states.contains(.queued) {
            return .queued
        }
        if states.contains(.paused) {
            return .paused
        }
        // 到这里只可能剩 failed（已在上面排除全部完成与活动状态）。
        return .failed
    }
}

/// 下载记录分页游标：先按分组（未完成／已完成），组内按排序时间与身份 key 定位。
///
/// 未完成组的排序时间是最近一次入队时间，已完成组是完成时间；分组与时间分开存，
/// 作品完成时只移动自身，不会把未完成组里入队更早的作品挤到已完成组之后。
struct DownloadedComicCursor: Equatable, Sendable {
    let sortGroup: Int
    let sortAt: Date
    let identityKey: String
}

/// 一页下载记录聚合。
struct DownloadedComicPage: Sendable {
    let items: [DownloadedComicSummary]
    let nextCursor: DownloadedComicCursor?
}

import Foundation
import SwiftData

/// 一个章节的下载任务记录（下载持久化与调度的最小单位）。
///
/// 只保存身份、章节快照与状态；作品级状态由同一作品下的章节记录**聚合投影**得到，
/// 不单独维护作品状态表，避免双写不一致。下载进度是运行时的单位计数（章节信息＋分页＋页图片），
/// 由 manifest 在恢复时重建，不落库。
@Model
final class StoredDownload {
    #Index<StoredDownload>([\.sourceID, \.stateChangedAt])

    @Attribute(.unique) var identityKey: String
    var sourceID: String
    var comicID: String
    var chapterID: String

    /// 下载时捕获的章节标题/顺序快照；不随在线详情变化。
    var chapterTitleSnapshot: String
    var chapterOrderSnapshot: Int

    var stateRawValue: String
    var jobID: UUID?

    var createdAt: Date
    var stateChangedAt: Date

    init(
        request: DownloadChapterRequest,
        state: DownloadState,
        jobID: UUID?,
        now: Date,
    ) {
        let identity = request.identity
        identityKey = Self.key(for: identity)
        sourceID = identity.comic.sourceID.rawValue
        comicID = identity.comic.comicID
        chapterID = identity.chapterID
        chapterTitleSnapshot = request.chapterTitleSnapshot
        chapterOrderSnapshot = request.chapterOrderSnapshot
        stateRawValue = state.rawValue
        self.jobID = jobID
        createdAt = now
        stateChangedAt = now
    }

    /// 类型化的下载状态；无法识别的持久化值返回 `nil`（损坏记录），由读取方显式跳过。
    var state: DownloadState? {
        get { DownloadState(rawValue: stateRawValue) }
        set { stateRawValue = newValue?.rawValue ?? stateRawValue }
    }

    /// 还原完整章节身份；`sourceID` 无法识别时返回 `nil`（损坏记录）。
    var chapterIdentity: ChapterIdentity? {
        guard let sourceID = ComicSourceID(rawValue: sourceID) else {
            return nil
        }

        return ChapterIdentity(
            comic: ComicIdentity(sourceID: sourceID, comicID: comicID),
            chapterID: chapterID,
        )
    }

    /// 长度前缀让任意两个完整章节身份都不会拼接碰撞（与 `StoredReadingHistory.key` 同款）。
    static func key(for identity: ChapterIdentity) -> String {
        let source = identity.comic.sourceID.rawValue
        let comic = identity.comic.comicID
        let chapter = identity.chapterID
        return "\(source.count):\(source)\(comic.count):\(comic)\(chapter.count):\(chapter)"
    }
}

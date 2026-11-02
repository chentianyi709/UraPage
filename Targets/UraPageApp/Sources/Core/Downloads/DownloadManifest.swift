import Foundation

/// 一个章节的下载清单：章节内所有已落盘页面的索引。
///
/// 它是章节页文件的**唯一索引**：先写页文件、再原子更新清单；章节可读状态由 SwiftData `completed` 状态决定。
/// 相对路径只相对章节目录，读取时必须做 containment 校验，拒绝绝对路径、`..` 与越界。
struct DownloadManifest: Codable, Sendable {
    /// 单页资产条目。
    struct PageEntry: Codable, Sendable {
        /// 来源给出的页面 ID（`PageIdentity.pageID`）。
        let pageID: String

        /// 章内零基序号；用于排序与缺页检测。
        let index: Int

        /// 相对章节目录的文件名；不包含目录分隔符。
        let relativePath: String
    }

    let chapterID: String
    var totalPageCount: Int
    var pages: [PageEntry]
}

/// 章节清单的增量提交状态：累加已落盘页条目，并决定何时原子提交。
///
/// 清单是页文件的唯一索引，提交粒度直接决定意外终止后的重下范围：距上次提交满 `commitInterval`
/// 或新增 `commitPageCount` 页即提交一次，批次边界与章节结束由调用方强制提交；
/// 提交失败只保留未提交状态，交给下一个提交点重试，章节结束前始终没有成功提交才算失败。
struct ChapterManifestCommit: Sendable {
    /// 距上次提交的最长时间间隔。
    static let commitInterval: TimeInterval = 0.75
    /// 两次提交之间允许累计的最大页数。
    static let commitPageCount = 8

    private(set) var entries: [String: DownloadManifest.PageEntry]
    private var committedPageCount: Int?
    private var lastCommitAt: Date = .distantPast

    init(entries: [String: DownloadManifest.PageEntry] = [:]) {
        self.entries = entries
    }

    /// 清单是否已覆盖全部已落盘页；章节结束据此判定能否算完成。
    var isFullyCommitted: Bool {
        committedPageCount == entries.count
    }

    /// 记入一页已落盘条目；同一页重复落盘只覆盖同一个键。
    mutating func record(_ entry: DownloadManifest.PageEntry) {
        entries[entry.pageID] = entry
    }

    /// 现在是否该写盘；`force` 用于批次边界与章节结束。
    func shouldCommit(force: Bool) -> Bool {
        guard entries.count != committedPageCount else { return false }
        guard !force else { return true }

        return entries.count - (committedPageCount ?? 0) >= Self.commitPageCount
            || Date().timeIntervalSince(lastCommitAt) >= Self.commitInterval
    }

    /// 提交成功后登记覆盖范围；失败不调用，留给下一个提交点重试。
    mutating func markCommitted() {
        committedPageCount = entries.count
        lastCommitAt = Date()
    }
}

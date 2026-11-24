import Foundation
import SwiftData

// MARK: - 无法读取的记录清理（设置页手动触发）

extension DownloadPersistence {
    /// 统计无法读取的下载记录：作品行（身份不可识别或封面引用无法解码）与将随之删除的章节行。
    ///
    /// 与读取端使用同一判定：作品行不可读时该作品在列表与调度中都不可用，
    /// 其章节行也无法通过任何入口读到，因此统计与清理按「作品及其全部章节」成组处理。
    func unreadableRecords() throws -> UnreadableDownloadRecords {
        let (works, workKeys) = try fetchUnreadableWorks()
        let downloads = try modelContext.fetch(FetchDescriptor<StoredDownloadChapter>())
        return UnreadableDownloadRecords(
            workCount: works.count,
            chapterCount: downloads.count {
                $0.chapterIdentity == nil || workKeys.contains(Self.workKey(of: $0))
            },
        )
    }

    /// 删除无法读取的下载记录；返回统计与被删除作品的原始身份（调用方据此删除其资产目录）。
    ///
    /// 只删不可读的成组记录：正常作品与正常章节不参与清理，也不会被顺带删除。
    func removeUnreadableRecords() throws -> (
        records: UnreadableDownloadRecords,
        removedWorkIdentities: [UnreadableWorkIdentity],
    ) {
        do {
            let (works, workKeys) = try fetchUnreadableWorks()
            var chapterCount = 0
            for download in try modelContext.fetch(FetchDescriptor<StoredDownloadChapter>()) {
                guard download.chapterIdentity == nil || workKeys.contains(Self.workKey(of: download))
                else { continue }

                modelContext.delete(download)
                chapterCount += 1
            }
            for work in works {
                modelContext.delete(work)
            }
            guard !works.isEmpty || chapterCount > 0 else {
                return (UnreadableDownloadRecords(workCount: 0, chapterCount: 0), [])
            }

            try saveChanges()
            return (
                UnreadableDownloadRecords(workCount: works.count, chapterCount: chapterCount),
                works.map { UnreadableWorkIdentity(sourceID: $0.sourceID, comicID: $0.comicID) },
            )
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    /// 无法读取的作品行与其作品 key（章节行按 key 判断归属）。
    private func fetchUnreadableWorks() throws
        -> (works: [StoredDownloadWork], workKeys: Set<DownloadWorkKey>) {
        let works = try modelContext.fetch(FetchDescriptor<StoredDownloadWork>())
            .filter(Self.isUnreadable)
        return (
            works,
            Set(works.map { DownloadWorkKey(sourceID: $0.sourceID, comicID: $0.comicID) }),
        )
    }

    /// 作品行是否无法读取：身份不可识别（来源被移除）或封面引用无法解码。
    private static func isUnreadable(_ work: StoredDownloadWork) -> Bool {
        work.identity == nil
            || (try? JSONDecoder().decode(ComicImageSource.self, from: work.coverReferenceData)) == nil
    }
}

// MARK: - 用户删除（下载记录）

extension DownloadPersistence {
    /// 删除一个作品的全部下载记录（作品行与其全部章节行）。
    ///
    /// 章节行与作品行分属两个模型、没有级联关系，按 sourceID + comicID 一并删除；
    /// 没有该作品的任何记录时返回 false（幂等空操作）。资产目录删除是调用方
    /// （`DownloadManager.remove`）的职责，在记录删除成功后尽力处理。
    @discardableResult
    func removeWork(for comic: ComicIdentity) throws -> Bool {
        let sourceID = comic.sourceID.rawValue
        let comicID = comic.comicID
        do {
            let workCount = try modelContext.fetchCount(
                FetchDescriptor<StoredDownloadWork>(
                    predicate: #Predicate { $0.sourceID == sourceID && $0.comicID == comicID },
                ),
            )
            let chapterCount = try modelContext.fetchCount(
                FetchDescriptor<StoredDownloadChapter>(
                    predicate: #Predicate { $0.sourceID == sourceID && $0.comicID == comicID },
                ),
            )
            guard workCount > 0 || chapterCount > 0 else { return false }

            // 批量删除直接落到库上、不物化行对象：删除一部多章作品从「N 次对象删除＋N 条语句」
            // 降到两条语句。代价是记录在 save 之前就已删除、不能再回滚，所以删除之后不再执行
            // 可能抛错的步骤：本操作不改章节状态，没有需要重算的投影，直接保存即可。
            try modelContext.delete(
                model: StoredDownloadChapter.self,
                where: #Predicate { $0.sourceID == sourceID && $0.comicID == comicID },
            )
            try modelContext.delete(
                model: StoredDownloadWork.self,
                where: #Predicate { $0.sourceID == sourceID && $0.comicID == comicID },
            )
            try modelContext.save()
            return true
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    /// 删除全部下载记录（作品行与章节行），返回删除的作品数。
    ///
    /// 资产目录删除由调用方（`DownloadManager.removeAll`）在记录删除成功后尽力完成。
    /// 批量删除直接落到库上、不物化行对象：几百部作品、数千章节时实测 290–772 ms → 18–19 ms
    /// （见 2026-11-21 探针对照）。代价是删除在 `save()` 之前就已生效、不能再回滚，
    /// 因此这里把可能失败的步骤（计数）全部放在删除之前，删除之后只剩保存；
    /// 调用方失败重试时会读到空表并得到 0，不会重复删除。
    @discardableResult
    func removeAllWorks() throws -> Int {
        // 待刷新投影全部失效：作品行即将删除，没有必要再重算。
        pendingProjectionKeys.removeAll()
        do {
            let workCount = try modelContext.fetchCount(FetchDescriptor<StoredDownloadWork>())
            try modelContext.delete(model: StoredDownloadChapter.self)
            try modelContext.delete(model: StoredDownloadWork.self)
            try modelContext.save()
            return workCount
        } catch {
            modelContext.rollback()
            throw error
        }
    }
}

/// 无法读取的下载记录统计（设置页「清理其他数据」的预览与结果共用）。
struct UnreadableDownloadRecords: Equatable, Sendable {
    let workCount: Int
    let chapterCount: Int

    var totalCount: Int {
        workCount + chapterCount
    }
}

/// 被清理作品的原始来源与作品字符串；来源已不可识别时只能按字符串定位资产目录。
struct UnreadableWorkIdentity: Equatable, Sendable {
    let sourceID: String
    let comicID: String
}

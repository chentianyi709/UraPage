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
        let downloads = try modelContext.fetch(FetchDescriptor<StoredDownload>())
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
            for download in try modelContext.fetch(FetchDescriptor<StoredDownload>()) {
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
    private func fetchUnreadableWorks() throws -> (works: [StoredDownloadedComic], workKeys: Set<String>) {
        let works = try modelContext.fetch(FetchDescriptor<StoredDownloadedComic>())
            .filter(Self.isUnreadable)
        return (
            works,
            Set(works.map { StoredDownloadedComic.key(sourceID: $0.sourceID, comicID: $0.comicID) }),
        )
    }

    /// 作品行是否无法读取：身份不可识别（来源被移除）或封面引用无法解码。
    private static func isUnreadable(_ work: StoredDownloadedComic) -> Bool {
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
        do {
            let work = try fetchWork(key: StoredDownloadedComic.key(for: comic))
            let downloads = try fetchDownloads(for: comic)
            guard work != nil || !downloads.isEmpty else { return false }

            for download in downloads {
                modelContext.delete(download)
            }
            if let work {
                modelContext.delete(work)
            }
            try saveChanges()
            return true
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    /// 删除全部下载记录（作品行与章节行），返回删除的作品数。
    ///
    /// 资产目录删除由调用方（`DownloadManager.removeAll`）在记录删除成功后尽力完成；
    /// 删除或保存失败时回滚，记录保持原样，调用方可原样重试。
    @discardableResult
    func removeAllWorks() throws -> Int {
        // 待刷新投影全部失效：作品行即将删除，没有必要再重算。
        pendingProjectionKeys.removeAll()
        do {
            let works = try modelContext.fetch(FetchDescriptor<StoredDownloadedComic>())
            let downloads = try modelContext.fetch(FetchDescriptor<StoredDownload>())
            for download in downloads {
                modelContext.delete(download)
            }
            for work in works {
                modelContext.delete(work)
            }
            try modelContext.save()
            return works.count
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

import Foundation
import Observation

/// 设置页「清理其他数据」的页面级 owner。
///
/// 统计是**全表检查**（逐行校验记录可读性、比较资产目录与记录）加一次临时目录枚举
/// （导出残留），只在用户点击「清理其他数据」时执行：打开设置页不做任何扫描，检查结果只服务
/// 本次点击的确认弹窗与清理后的重新统计。删除全部由用户显式触发，不做自动删除；正常数据不会被删除。
/// 导出残留只取早于本次启动基准的目录（`TemporaryFiles.launchCutoff`），这是清理导出残留的**唯一入口**
/// （启动清理不再扫描导出目录），本次会话正在进行的导出不受影响。
@MainActor
@Observable
final class DataCleanupStore {
    /// 检查阶段。
    enum Phase: Equatable {
        /// 尚未检查（打开设置页时的初始状态）。
        case idle

        case scanning
        case failed
        case scanned(
            downloads: UnreadableDownloadRecords,
            orphanedAssetCount: Int,
            readingHistory: Int,
            exportResidue: Int,
        )
    }

    private(set) var phase: Phase = .idle
    private(set) var isCleaning = false

    @ObservationIgnored private let manager: DownloadManager
    @ObservationIgnored private let historyStore: ReadingHistoryStore

    init(manager: DownloadManager, historyStore: ReadingHistoryStore) {
        self.manager = manager
        self.historyStore = historyStore
    }

    /// 待清理的项目总数（记录条数＋孤立资产目录数＋导出残留目录数）；未检查、检查中或检查失败时为 `nil`。
    var pendingCount: Int? {
        guard case let .scanned(downloads, orphanedAssetCount, readingHistory, exportResidue) = phase else {
            return nil
        }

        return downloads.totalCount + orphanedAssetCount + readingHistory + exportResidue
    }

    /// 检查或清理进行中；此时不接受新的检查与清理请求。
    var isBusy: Bool {
        phase == .scanning || isCleaning
    }

    /// 执行全表检查；成功进入 `.scanned`，失败进入 `.failed`。
    @discardableResult
    func scan() async -> Bool {
        guard !isBusy else { return false }

        return await performScan()
    }

    /// 让检查结果失效：外部清除（下载记录／阅读记录）改变了可清理的数据量，
    /// 下次点击「清理其他数据」必须重新检查，页面也不再显示过期项数。
    ///
    /// 检查或清理进行中不打断，结束后由 `clean()` 自己重扫。
    func invalidateScan() {
        guard !isBusy else { return }

        phase = .idle
    }

    /// 执行清理；返回实际删除的项目数（记录条数＋孤立资产目录数＋导出残留目录数），
    /// 任一记录侧失败返回 `nil`。
    ///
    /// 下载记录先删除，再清理因此产生的孤立资产目录（记录删除成功但资产删除失败的作品）；
    /// 阅读记录与导出残留各自并行执行。每类独立提交：一侧失败不影响另一侧已删除的结果；
    /// 导出残留失败只由 `TemporaryFiles` 记日志。结束后重新检查，让页面对剩余数量保持真实。
    func clean() async -> Int? {
        guard !isBusy else { return nil }

        isCleaning = true
        async let readingHistory = removeUnreadableReadingHistory()
        async let exportResidue = TemporaryFiles.removeExportResidue()
        let downloadCount = await removeUnreadableDownloads()
        let orphanedAssetCount = await removeOrphanedAssets()
        let (historyCount, exportCount) = await (readingHistory, exportResidue)
        isCleaning = false

        _ = await performScan()

        guard let downloadCount, let orphanedAssetCount, let historyCount else { return nil }

        return downloadCount + orphanedAssetCount + historyCount + exportCount
    }

    /// 删除无法读取的下载记录（连带其已不可访问的资产目录）；失败返回 `nil`。
    private func removeUnreadableDownloads() async -> Int? {
        do {
            return try await manager.removeUnreadableRecords().totalCount
        } catch {
            AppLogger.error(
                "清理无法读取的下载记录失败，errorType=\(String(reflecting: type(of: error)))",
                category: "Settings.Cleanup",
            )
            return nil
        }
    }

    /// 删除没有对应下载记录的孤立资产目录；失败返回 `nil`。
    private func removeOrphanedAssets() async -> Int? {
        do {
            return try await manager.removeOrphanedAssets()
        } catch {
            AppLogger.error(
                "清理孤立下载资产失败，errorType=\(String(reflecting: type(of: error)))",
                category: "Settings.Cleanup",
            )
            return nil
        }
    }

    /// 删除无法读取的阅读记录；失败返回 `nil`。
    private func removeUnreadableReadingHistory() async -> Int? {
        do {
            return try await historyStore.removeUnreadableRecords()
        } catch {
            AppLogger.error(
                "清理无法读取的阅读记录失败，errorType=\(String(reflecting: type(of: error)))",
                category: "Settings.Cleanup",
            )
            return nil
        }
    }

    private func performScan() async -> Bool {
        phase = .scanning
        do {
            async let downloads = manager.unreadableRecords()
            async let orphanedAssetCount = manager.orphanedAssetCount()
            async let readingHistory = historyStore.unreadableRecordCount()
            async let exportResidue = TemporaryFiles.exportResidueCount()
            phase = try await .scanned(
                downloads: downloads,
                orphanedAssetCount: orphanedAssetCount,
                readingHistory: readingHistory,
                exportResidue: exportResidue,
            )
            return true
        } catch {
            AppLogger.error(
                "清理其他数据检查失败，errorType=\(String(reflecting: type(of: error)))",
                category: "Settings.Cleanup",
            )
            phase = .failed
            return false
        }
    }
}

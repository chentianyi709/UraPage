import Foundation
import Observation

/// 导出完成的压缩包产物；清空时由 owner 删除临时文件。
struct ExportedArchive: Equatable, Sendable {
    let url: URL
}

/// 「下载记录」导出的一次会话：封面进度与产物压缩包。
///
/// 页面在首次激活时创建并长期持有。导出在后台执行器上运行，这里只维护封面进度所需的
/// 状态与待分享的压缩包；导出不提供取消入口，任务启动前登记临时目录和资产 lease，
/// 失败、页面释放或 `finishSharing()` 都删除该目录，任务结束释放 lease。
@Observable
@MainActor
final class DownloadsExportModel {
    /// 导出进度：已完成的整数百分比；`nil` 表示还没拿到总页数（准备阶段）。
    /// 「是否正在导出」由 `exportingIdentity` 表达，不依赖这里的 `nil`。
    private(set) var progress: Int?

    /// 非空表示正在导出：只有该作品的封面显示导出进度。
    private(set) var exportingIdentity: ComicIdentity?

    /// 导出完成后待分享的压缩包。
    private(set) var archive: ExportedArchive?

    @ObservationIgnored private let manager: DownloadManager
    @ObservationIgnored private var exportTask: Task<Void, Never>?
    @ObservationIgnored private var exportedDirectoryURL: URL?

    init(manager: DownloadManager) {
        self.manager = manager
    }

    deinit {
        exportTask?.cancel()
        // 已完成但未分享的产物也随 owner 释放删除，避免临时目录留到下次启动清理。
        if let exportedDirectoryURL {
            try? FileManager.default.removeItem(at: exportedDirectoryURL)
        }
    }

    /// 开始一次导出；已有导出进行中时不重复启动。
    func begin(comic: ComicIdentity) {
        guard exportTask == nil else { return }

        // 清掉上一次已生成但未分享的产物，避免旧 archive 继续占着 sheet 与临时目录。
        finishSharing()

        // 目录在启动导出前就登记到 owner：后台任务无论成功、失败还是 owner 提前释放，
        // 都不会出现「压缩包已生成但无人知道临时目录」的泄漏窗口。
        let directory = TemporaryFiles.makeExportDirectoryURL()
        exportedDirectoryURL = directory
        exportingIdentity = comic
        progress = nil
        let (updates, updatesContinuation) = AsyncStream.makeStream(
            of: Int.self,
            bufferingPolicy: .bufferingNewest(1),
        )
        let manager = manager
        let leaseSessionID = UUID()

        exportTask = Task { [weak self] in
            // 进度是高频事件：用单一消费者保持最新值，避免每页都跨 actor 更新一次状态。
            let observer = Task { @MainActor [weak self] in
                for await percent in updates {
                    self?.progress = percent
                }
            }

            // 先登记 lease，再构建计划：导出读取资产期间，「清除下载记录」与单作品删除
            // 会被 lease 门禁挡住，不会删掉正在读取的文件。
            await manager.acquireExportAssetLease(for: comic, sessionID: leaseSessionID)
            defer {
                updatesContinuation.finish()
                observer.cancel()
            }

            do {
                let plan = try await manager.makeExportPlan(for: comic)
                self?.progress = 0

                let archiveURL = try await DownloadedComicExporter.export(plan, in: directory) { percent in
                    updatesContinuation.yield(percent)
                }
                self?.complete(archiveURL)
            } catch is CancellationError {
                self?.failExport()
            } catch {
                AppLogger.error(
                    "下载记录导出失败，errorType=\(String(reflecting: type(of: error)))",
                    category: "App.Download",
                )
                self?.failExport()
                ToastCenter.shared.show(
                    (error as? ComicExportError)?.message ?? "导出失败，请稍后重试",
                    type: .error,
                )
            }

            await manager.releaseExportAssetLease(sessionID: leaseSessionID)
        }
    }

    /// 分享结束后清空产物并删除临时目录；重复调用无副作用。
    func finishSharing() {
        archive = nil
        guard let exportedDirectoryURL else { return }

        self.exportedDirectoryURL = nil
        try? FileManager.default.removeItem(at: exportedDirectoryURL)
    }

    private func complete(_ archiveURL: URL) {
        finishExport()
        archive = ExportedArchive(url: archiveURL)
    }

    /// 失败／取消后同时清掉状态与已登记的临时目录；导出器可能已经删过，重复删除无副作用。
    private func failExport() {
        finishExport()
        finishSharing()
    }

    private func finishExport() {
        exportTask = nil
        exportingIdentity = nil
        progress = nil
    }
}

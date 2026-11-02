import Foundation
import Observation

/// 通用设置「清理」分区的页面状态与动作 owner。
///
/// 四个清理入口的进行态、错误文案与「清理其他数据」的检查结果集中在这里；
/// 视图只负责展示与二次确认，避免把下载／阅读历史的错误映射散落在页面里。
@MainActor
@Observable
final class GeneralCleanupModel {
    @ObservationIgnored private let imageCacheSettings: ImageCacheSettingsStore
    @ObservationIgnored private let readingHistorySettings: ReadingHistorySettingsStore
    @ObservationIgnored private let downloadManager: DownloadManager
    @ObservationIgnored private let readingHistoryStore: ReadingHistoryStore

    private(set) var isClearingReadingHistory = false
    private(set) var isClearingDownloads = false

    /// 下载资产占用状态；进入分区时读取，清除下载后刷新。
    private(set) var downloadsUsageState: StorageUsageState = .loading

    /// 下载占用读取代次；进入页面的慢扫描不能覆盖清除后发起的新结果。
    @ObservationIgnored private var downloadsUsageGeneration = 0

    /// 「清理其他数据」右侧状态；文案与图标由页面映射。
    enum OtherDataStatus: Equatable {
        /// 尚未检查。
        case idle
        case scanning
        case failed
        /// 待清理项数。
        case count(Int)
    }

    /// 「清理其他数据」的二次确认是否展示；检查完成后才置位。
    var showsCleanupConfirmation = false

    /// 「清理其他数据」的页面级 owner；打开设置页时只创建，不做全表扫描。
    private(set) var cleanup: DataCleanupStore?

    init(
        imageCacheSettings: ImageCacheSettingsStore,
        readingHistorySettings: ReadingHistorySettingsStore,
        downloadManager: DownloadManager,
        readingHistoryStore: ReadingHistoryStore,
    ) {
        self.imageCacheSettings = imageCacheSettings
        self.readingHistorySettings = readingHistorySettings
        self.downloadManager = downloadManager
        self.readingHistoryStore = readingHistoryStore
    }

    /// 页面出现时刷新占用并创建清理 owner；检查仍留到用户点击时执行。
    ///
    /// 图片缓存占用与下载资产扫描互不依赖，并行执行，不让较慢的扫盘拖住另一行的展示。
    func prepare() async {
        if cleanup == nil {
            cleanup = DataCleanupStore(
                manager: downloadManager,
                historyStore: readingHistoryStore,
            )
        }

        async let cacheUsage: Void = imageCacheSettings.refreshUsage()
        async let downloadsUsage: Void = refreshDownloadsUsage()
        await cacheUsage
        await downloadsUsage
    }

    var isClearingCache: Bool {
        imageCacheSettings.isClearing
    }

    /// 数据类清理（下载、阅读记录、其他数据）是否正在进行。
    ///
    /// 三个入口删除或扫描同一批持久化数据，同一时间只允许一个：
    /// 避免「清理其他数据」检查期间另一个入口删掉待清理项，或两边并发删除导致计数失真。
    var isClearingData: Bool {
        isClearingDownloads || isClearingReadingHistory || (cleanup?.isBusy ?? false)
    }

    /// 图片缓存占用状态；大小文案与图标由页面映射。
    var cacheUsageState: StorageUsageState {
        imageCacheSettings.diskUsageState
    }

    /// 读取下载资产占用；失败显示失败图标，不能把读失败当成 0（否则会被误认为已清空）。
    ///
    /// 只回写最后一次发起的结果：进入页面的慢扫描可能在清除之后才返回，不能覆盖清除后的新大小。
    private func refreshDownloadsUsage() async {
        downloadsUsageGeneration &+= 1
        let generation = downloadsUsageGeneration

        do {
            let bytes = try await downloadManager.assetUsageBytes()
            guard generation == downloadsUsageGeneration, !Task.isCancelled else { return }

            downloadsUsageState = .available(bytes: bytes)
        } catch {
            guard generation == downloadsUsageGeneration, !Task.isCancelled else { return }

            AppLogger.warning(
                "下载资产占用读取失败，errorType=\(String(reflecting: type(of: error)))",
                category: "Settings.Cleanup",
            )
            downloadsUsageState = .failed
        }
    }

    func clearCache() async {
        guard !isClearingCache else { return }
        guard await imageCacheSettings.clearCache() else {
            ToastCenter.shared.show("清除失败，请稍后重试。", type: .error)
            return
        }

        ToastCenter.shared.show("已清除图片缓存", type: .success)
    }

    func clearReadingHistory() async {
        guard !isClearingData else { return }

        isClearingReadingHistory = true
        let succeeded = await readingHistorySettings.clearAll()
        isClearingReadingHistory = false

        // 阅读记录清空后，「清理其他数据」按旧结果统计的项数已不成立。
        cleanup?.invalidateScan()

        ToastCenter.shared.show(
            succeeded ? "已清除阅读记录" : "清除失败，请稍后重试。",
            type: succeeded ? .success : .error,
        )
    }

    func clearDownloads() async {
        guard !isClearingData else { return }

        isClearingDownloads = true
        defer { isClearingDownloads = false }

        do {
            _ = try await downloadManager.removeAll()
            ToastCenter.shared.show("已清除下载记录", type: .success)
        } catch {
            AppLogger.error(
                "清除下载记录失败，errorType=\(String(reflecting: type(of: error)))",
                category: "Settings.Cleanup",
            )
            ToastCenter.shared.show(Self.failureMessage(for: error), type: .error)
        }

        // 「清理其他数据」的孤立资产与不可读记录统计已随删除变化，下次点击需要重查。
        cleanup?.invalidateScan()

        // 资产删除可能只完成一部分，先回到加载态再展示真实占用，避免短暂显示旧大小。
        downloadsUsageState = .loading
        await refreshDownloadsUsage()
    }

    /// 点击「清理其他数据」：未检查时先全表检查；有内容才弹二次确认。
    func handleOtherDataTap() async {
        guard !isClearingData, let cleanup else { return }

        if cleanup.pendingCount == nil {
            guard await cleanup.scan() else {
                ToastCenter.shared.show("检查失败，请稍后重试。", type: .error)
                return
            }
        }
        guard let pending = cleanup.pendingCount, pending > 0 else {
            ToastCenter.shared.show("没有需要清理的数据")
            return
        }

        showsCleanupConfirmation = true
    }

    /// 用户确认后执行清理，并按结果给出提示。
    func cleanOtherData() async {
        guard !isClearingData, let cleanup else { return }
        guard let removedCount = await cleanup.clean() else {
            ToastCenter.shared.show("清理失败，请稍后重试。", type: .error)
            return
        }

        // 清理会删除不可读下载记录与孤立资产，占用数字需要重新读取。
        await refreshDownloadsUsage()

        ToastCenter.shared.show("已清理 \(removedCount) 项", type: .success)
    }

    var otherDataActionTitle: String {
        guard let cleanup else { return "清理其他数据" }

        if cleanup.isCleaning {
            return "正在清理其他数据..."
        }
        if case .scanning = cleanup.phase {
            return "正在检查其他数据..."
        }

        return "清理其他数据"
    }

    /// 「清理其他数据」右侧状态：待检查／检查中／检查失败／无／具体项数。
    var otherDataStatus: OtherDataStatus {
        guard let cleanup else { return .idle }

        switch cleanup.phase {
        case .idle:
            return .idle

        case .scanning:
            return .scanning

        case .failed:
            return .failed

        case .scanned:
            // 与 `pendingCount` 同源，避免两处各算一遍合计。
            return .count(cleanup.pendingCount ?? 0)
        }
    }

    var otherDataDisabled: Bool {
        guard let cleanup else { return true }

        // 其它数据入口正在清除时同样禁用；检查结果为空则没有可清理项。
        return isClearingData || cleanup.pendingCount == 0
    }

    /// 二次确认的明细：下载记录含其资产，阅读记录只删记录行；
    /// 孤立资产与导出残留只在有内容时列出，避免用户误以为每次都会删除这类数据。
    var otherDataCleanupMessage: String {
        guard case let .scanned(downloads, orphanedAssetCount, readingHistory, exportResidue) = cleanup?.phase
        else {
            return "将删除无法读取的记录、无记录的孤立下载资产及其本地文件；正常数据不会被删除。"
        }

        var parts = [
            "将删除无法读取的下载记录 \(downloads.totalCount) 条（含其本地资产）",
            "阅读记录 \(readingHistory) 条",
        ]
        if orphanedAssetCount > 0 {
            parts.append("无记录的孤立下载资产 \(orphanedAssetCount) 项")
        }
        if exportResidue > 0 {
            parts.append("导出中断残留的压缩包 \(exportResidue) 份")
        }

        return parts.joined(separator: "、") + "；正常数据不会被删除。"
    }

    /// 清除下载失败时优先使用资产／删除错误自带的提示，避免用户对着「稍后重试」反复尝试。
    private static func failureMessage(for error: any Error) -> String {
        if let assetError = error as? DownloadAssetError,
           let message = assetError.removalMessage {
            return message
        }
        if let removalError = error as? DownloadRemovalError {
            return removalError.message
        }

        return "清除失败，请稍后重试。"
    }
}

import Foundation

/// 临时文件规则：页传输与下载资产共用一套「同目录 `*.tmp`」命名。
///
/// - 页传输：系统临时目录下的 `urapage-page-<uuid>.tmp`，来源处理完成后立即删除；
/// - 下载资产：正式文件同目录下的 `<目标名>.<uuid>.tmp`，写入／复制完成后替换为正式文件；
/// - 作品导出：系统临时目录下的 `urapage-export-<uuid>/` 目录（内含导出的压缩包），
///   分享结束或导出失败后删除；
/// - 启动清理：只处理页传输残留与资产写入／复制残留——这两类没有用户入口，只能在启动时回收；
///   两类各自扫描、并行执行，只删早于 `launchCutoff`（本次启动的清理基准）的条目，
///   单个条目失败只记录日志，不阻断其余清理。
/// - 手动清理：导出残留**只**由设置页「清理其他数据」按同一基准清理，启动时不再扫描导出目录，
///   避免启动做一次用户也能手动触发的全目录扫描；同一基准保证不会碰到本次会话正在进行的导出。
nonisolated enum TemporaryFiles {
    /// 页传输文件前缀；只有页传输创建的文件使用该前缀。
    private static let pageTransferPrefix = "urapage-page-"

    /// 作品导出目录前缀；导出目录与其中的压缩包只使用这一前缀。
    private static let exportDirectoryPrefix = "urapage-export-"

    /// 本次启动的临时文件清理基准时刻。
    ///
    /// 由 App 入口初始化时显式读取（`UraPageApp.init`），早于任何 UI 交互与导出；本次会话创建的
    /// 导出目录都晚于它，设置页手动清理不会误删进行中的导出。`static let` 只求值一次，后续访问
    /// 不会改变基准；不要在 App 启动后依赖首次访问来固定它。
    static let launchCutoff = Date()

    /// 临时文件扩展名；资产写入／复制与启动清理共用这一约定。
    private static let temporaryExtension = "tmp"

    private static let resourceKeys: Set<URLResourceKey> = [
        .isRegularFileKey,
        .isDirectoryKey,
        .isSymbolicLinkKey,
        .contentModificationDateKey,
    ]

    /// 页传输的单页临时文件 URL（系统临时目录）。
    static func makePageTransferURL() -> URL {
        FileManager.default.temporaryDirectory.appending(
            path: "\(pageTransferPrefix)\(UUID().uuidString.lowercased()).\(temporaryExtension)",
            directoryHint: .notDirectory,
        )
    }

    /// 资产写入／复制的临时文件 URL（与目标同目录）。
    static func makeAssetTemporaryURL(for destinationURL: URL) -> URL {
        destinationURL.deletingLastPathComponent().appending(
            path: "\(destinationURL.lastPathComponent).\(UUID().uuidString.lowercased()).\(temporaryExtension)",
            directoryHint: .notDirectory,
        )
    }

    /// 一次导出的临时目录（系统临时目录）；压缩包写在其中，分享结束或失败后整体删除。
    static func makeExportDirectoryURL() -> URL {
        FileManager.default.temporaryDirectory.appending(
            path: "\(exportDirectoryPrefix)\(UUID().uuidString.lowercased())",
            directoryHint: .isDirectory,
        )
    }

    /// 设置页「清理其他数据」用：早于本次启动基准的导出残留目录数量。
    @concurrent
    static func exportResidueCount() async -> Int {
        staleExportDirectories(createdBefore: launchCutoff).count
    }

    /// 设置页「清理其他数据」用：删除早于本次启动基准的导出残留目录（连同其中的压缩包）。
    @concurrent
    static func removeExportResidue() async -> Int {
        removeExportDirectories(createdBefore: launchCutoff)
    }

    /// 启动清理：页传输残留与资产写入／复制残留，两类各自扫描、并行执行。
    ///
    /// 导出残留不在这里处理：它可以从设置页「清理其他数据」手动清理，启动时不再重复扫描临时目录。
    @concurrent
    static func removeStaleFiles() async {
        let cutoff = launchCutoff
        async let pageTransferCount = removePageTransferFiles(createdBefore: cutoff)
        async let assetCount = removeAssetTemporaryFiles(createdBefore: cutoff)
        let (pageTransferRemoved, assetRemoved) = await (pageTransferCount, assetCount)
        guard pageTransferRemoved > 0 || assetRemoved > 0 else { return }

        AppLogger.info(
            "启动临时文件清理完成，pageTransfer=\(pageTransferRemoved)，asset=\(assetRemoved)",
            category: "App.Download",
        )
    }

    /// 早于 `cutoff` 的导出残留目录；按固定前缀识别，符号链接与非目录项都不算。
    private static func staleExportDirectories(createdBefore cutoff: Date) -> [URL] {
        let children: [URL]
        do {
            children = try FileManager.default.contentsOfDirectory(
                at: FileManager.default.temporaryDirectory,
                includingPropertiesForKeys: Array(resourceKeys),
                options: [.skipsHiddenFiles],
            )
        } catch {
            AppLogger.warning(
                "导出临时目录读取失败，errorType=\(String(reflecting: type(of: error)))",
                category: "App.Download",
            )
            return []
        }

        return children.filter {
            $0.lastPathComponent.hasPrefix(exportDirectoryPrefix) && isStaleDirectory(
                $0,
                createdBefore: cutoff,
            )
        }
    }

    /// 导出残留目录整目录删除，返回删除数量。
    private static func removeExportDirectories(createdBefore cutoff: Date) -> Int {
        var removedCount = 0
        for childURL in staleExportDirectories(createdBefore: cutoff) {
            if removeStaleDirectory(at: childURL, createdBefore: cutoff) {
                removedCount += 1
            }
        }
        return removedCount
    }

    /// 页传输文件位于系统临时目录，按固定前缀识别；与资产残留并行执行。
    @concurrent
    private static func removePageTransferFiles(createdBefore cutoff: Date) async -> Int {
        let children: [URL]
        do {
            children = try FileManager.default.contentsOfDirectory(
                at: FileManager.default.temporaryDirectory,
                includingPropertiesForKeys: Array(resourceKeys),
                options: [.skipsHiddenFiles],
            )
        } catch {
            AppLogger.warning(
                "页传输临时目录读取失败，errorType=\(String(reflecting: type(of: error)))",
                category: "App.Download",
            )
            return 0
        }

        var removedCount = 0
        for childURL in children where childURL.lastPathComponent.hasPrefix(pageTransferPrefix) {
            if removeStaleFile(at: childURL, createdBefore: cutoff) {
                removedCount += 1
            }
        }
        return removedCount
    }

    /// 资产目录按受控目录遍历，只删除 `*.tmp` 且解析符号链接后仍在根目录内的普通文件；与页传输残留并行执行。
    @concurrent
    private static func removeAssetTemporaryFiles(createdBefore cutoff: Date) async -> Int {
        // `FileManager.DirectoryEnumerator` 的迭代器在异步上下文不可用；遍历本身是同步 IO，
        // 在本并发函数里直接调用即可，不会回到调用者执行器。
        deleteTemporaryAssets(createdBefore: cutoff)
    }

    /// 同步遍历资产目录并删除残留；只由上面的并发入口调用。
    private static func deleteTemporaryAssets(createdBefore cutoff: Date) -> Int {
        guard let base = try? DownloadAssetPaths.baseDirectory(),
              let enumerator = FileManager.default.enumerator(
                  at: base,
                  includingPropertiesForKeys: Array(resourceKeys),
                  options: [.skipsPackageDescendants],
              )
        else { return 0 }

        let resolvedBase = base.resolvingSymlinksInPath()
        var removedCount = 0
        for case let url as URL in enumerator {
            guard url.pathExtension == temporaryExtension,
                  DownloadAssetPaths.isContained(url.resolvingSymlinksInPath(), in: resolvedBase)
            else { continue }

            if removeStaleFile(at: url, createdBefore: cutoff) {
                removedCount += 1
            }
        }
        return removedCount
    }

    /// 删除早于 `cutoff` 的普通文件；符号链接、目录与更新中的文件都不处理。
    private static func removeStaleFile(at url: URL, createdBefore cutoff: Date) -> Bool {
        guard let values = try? url.resourceValues(forKeys: resourceKeys),
              values.isRegularFile == true,
              values.isSymbolicLink != true,
              let modificationDate = values.contentModificationDate,
              modificationDate < cutoff
        else { return false }

        do {
            try FileManager.default.removeItem(at: url)
            return true
        } catch {
            AppLogger.warning(
                "临时文件清理失败，name=\(url.lastPathComponent)，errorType=\(String(reflecting: type(of: error)))",
                category: "App.Download",
            )
            return false
        }
    }

    /// 是否是早于 `cutoff` 的普通目录；符号链接与更新中的目录都不算。
    private static func isStaleDirectory(_ url: URL, createdBefore cutoff: Date) -> Bool {
        guard let values = try? url.resourceValues(forKeys: resourceKeys),
              values.isDirectory == true,
              values.isSymbolicLink != true,
              let modificationDate = values.contentModificationDate,
              modificationDate < cutoff
        else { return false }

        return true
    }

    /// 删除早于 `cutoff` 的导出目录（连同其中的压缩包）。
    private static func removeStaleDirectory(at url: URL, createdBefore cutoff: Date) -> Bool {
        guard isStaleDirectory(url, createdBefore: cutoff) else { return false }

        do {
            try FileManager.default.removeItem(at: url)
            return true
        } catch {
            AppLogger.warning(
                "导出临时目录清理失败，name=\(url.lastPathComponent)，errorType=\(String(reflecting: type(of: error)))",
                category: "App.Download",
            )
            return false
        }
    }
}

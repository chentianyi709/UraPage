import Foundation

// MARK: - 孤儿目录与全部清理

extension DownloadAssetStore {
    /// 列出磁盘上没有对应下载记录的作品资产目录。
    ///
    /// `known` 必须包含持久化中的全部作品原始身份（含无法识别的来源），否则会把仍被记录
    /// 引用的目录误判成孤立资产。作品目录名由来源与作品 ID 计算，不能从磁盘反推身份，
    /// 因此按记录生成已知路径集合再比较。只返回真实目录，跳过符号链接与越界项。
    func orphanedComicDirectories(known: [DownloadAssetIdentity]) throws -> [URL] {
        let base = try DownloadAssetPaths.baseDirectory()
            .resolvingSymlinksInPath()
            .standardizedFileURL
        let knownPaths = try Set(known.map {
            try DownloadAssetPaths.comicDirectory(sourceID: $0.sourceID, comicID: $0.comicID)
                .resolvingSymlinksInPath()
                .standardizedFileURL
                .path
        })

        let sourceDirectories = try fileManager.contentsOfDirectory(
            at: base,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
        )
        var orphans: [URL] = []
        for sourceDirectory in sourceDirectories {
            guard try Self.isRealDirectory(sourceDirectory, containedIn: base, allowBase: false)
            else { continue }

            let resolvedSource = sourceDirectory.resolvingSymlinksInPath().standardizedFileURL
            let comicDirectories = try fileManager.contentsOfDirectory(
                at: sourceDirectory,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            )
            for comicDirectory in comicDirectories {
                guard try Self.isRealDirectory(
                    comicDirectory,
                    containedIn: resolvedSource,
                    allowBase: false,
                ) else { continue }

                let path = comicDirectory.resolvingSymlinksInPath().standardizedFileURL.path
                if !knownPaths.contains(path) {
                    orphans.append(comicDirectory)
                }
            }
        }
        return orphans
    }

    /// 删除一个孤立作品目录；仍被 lease 占用时拒绝。
    ///
    /// 孤儿的记录已经不存在，不能再用 `removeComicDirectory` 的身份入参；这里按目录路径
    /// 与 lease 作品的实际目录比对，保留离线阅读／导出期间的删除保护。
    func removeOrphanedDirectory(at url: URL) throws {
        let base = try DownloadAssetPaths.baseDirectory()
            .resolvingSymlinksInPath()
            .standardizedFileURL
        guard fileManager.fileExists(atPath: url.path) else { return }
        guard try Self.isRealDirectory(url, containedIn: base, allowBase: false) else { return }

        let targetPath = url.resolvingSymlinksInPath().standardizedFileURL.path
        for comic in leasedComicsBySession.values {
            guard let leasedURL = try? DownloadAssetPaths.comicDirectory(for: comic) else { continue }

            if leasedURL.resolvingSymlinksInPath().standardizedFileURL.path == targetPath {
                throw DownloadAssetError.assetLeased
            }
        }

        try fileManager.removeItem(at: url)
    }

    /// 删除全部作品的资产目录，返回删除的作品数；有活动 lease 时整体拒绝，不删除任何内容。
    ///
    /// 用于设置页「清除下载记录」：记录已经删除后才调用，失败只留下可由「清理其他数据」
    /// 回收的孤儿目录。根目录保留（`DownloadAssetPaths.baseDirectory` 缓存的 URL 继续有效），
    /// 删空的来源目录一并移除，下次下载时重新创建。
    @discardableResult
    func removeAllComicDirectories() throws -> Int {
        guard leasedComicsBySession.isEmpty else {
            throw DownloadAssetError.assetLeased
        }

        // 资产根目录来自 App 容器，但仍按外部磁盘输入处理：只删除真实的目录，
        // 跳过符号链接并在解析后做 containment 校验，避免被替换的目录把删除引到容器外。
        let base = try DownloadAssetPaths.baseDirectory()
            .resolvingSymlinksInPath()
            .standardizedFileURL
        let sourceDirectories = try fileManager.contentsOfDirectory(
            at: base,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
        )
        var removedCount = 0
        for sourceDirectory in sourceDirectories {
            guard try Self.isRealDirectory(sourceDirectory, containedIn: base, allowBase: false)
            else { continue }

            let resolvedSource = sourceDirectory.resolvingSymlinksInPath().standardizedFileURL

            let comicDirectories = try fileManager.contentsOfDirectory(
                at: sourceDirectory,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            )
            for comicDirectory in comicDirectories {
                guard try Self.isRealDirectory(
                    comicDirectory,
                    containedIn: resolvedSource,
                    allowBase: false,
                ) else { continue }

                try fileManager.removeItem(at: comicDirectory)
                removedCount += 1
            }

            if (try? fileManager.contentsOfDirectory(atPath: sourceDirectory.path).isEmpty) == true {
                try fileManager.removeItem(at: sourceDirectory)
            }
        }
        return removedCount
    }

    /// 只接受目录本身不是符号链接、解析后仍落在允许目录内的真实子目录。
    private static func isRealDirectory(
        _ url: URL,
        containedIn directory: URL,
        allowBase: Bool,
    ) throws -> Bool {
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else {
            return false
        }

        let resolved = url.resolvingSymlinksInPath().standardizedFileURL
        return DownloadAssetPaths.isContained(resolved, in: directory)
            && (allowBase || resolved != directory)
    }
}

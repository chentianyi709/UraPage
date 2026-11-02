import Foundation

/// 占用统计无法枚举资产根目录；只在本文件使用，页面按读取失败处理。
private enum DownloadAssetUsageError: Error {
    case enumerationFailed
}

// MARK: - 占用统计

extension DownloadAssetStore {
    /// 统计资产根目录的实际占用字节数，供设置页「清除下载记录」展示。
    ///
    /// 范围与「清除下载记录」的删除范围一致：全部作品目录（封面、章节页、manifest），
    /// 含已无下载记录的孤儿目录，因此该数字就是这次操作会释放的空间。
    /// 递归枚举按文件数线性耗时，标 `@concurrent` 离开资产 actor 执行，不挡住离线阅读取页与下载写入；
    /// 只读测量，不创建目录、不改变任何状态。符号链接不是常规文件，会被跳过，只可能影响数字、不会写到容器外。
    @concurrent
    nonisolated func assetUsageBytes() async throws -> Int {
        // 从未下载过时资产目录不存在，占用就是 0，不能因此建目录。
        guard let base = try DownloadAssetPaths.baseDirectoryIfExists()?
            .resolvingSymlinksInPath()
        else {
            return 0
        }
        guard let files = FileManager.default.enumerator(
            at: base,
            includingPropertiesForKeys: [
                .totalFileAllocatedSizeKey,
                .fileSizeKey,
                .isRegularFileKey,
            ],
        ) else {
            // 枚举失败是读取失败，不能返回 0 让页面误以为已经清空。
            throw DownloadAssetUsageError.enumerationFailed
        }

        var total = 0
        // 异步上下文不能用 `for-in`（`NSEnumerator.makeIterator()` 标了 noasync），逐项取。
        while let url = files.nextObject() as? URL {
            try Task.checkCancellation()
            let values: URLResourceValues
            do {
                values = try url.resourceValues(
                    forKeys: [
                        .totalFileAllocatedSizeKey,
                        .fileSizeKey,
                        .isRegularFileKey,
                    ],
                )
            } catch where DownloadAssetStore.isMissingFile(error) {
                // 扫描期间被并发下载或清除删掉的项不算读取失败，跳过即可。
                continue
            }
            guard values.isRegularFile == true else { continue }

            // 分配大小是系统口径的「磁盘占用」；拿不到时退回文件逻辑大小。
            total += values.totalFileAllocatedSize ?? values.fileSize ?? 0
        }

        return total
    }
}

import Foundation

/// 下载资产的磁盘 owner：章节正式文件、封面与资产 lease。
///
/// 路径规则由 `DownloadAssetPaths` 统一；manifest 读写与孤儿目录清理分别在同目录的
/// `DownloadAssetStore+Manifest.swift` 与 `DownloadAssetStore+Cleanup.swift`。
/// manifest 是已下载页的索引，续传不重新读取或校验页文件字节。
actor DownloadAssetStore {
    let fileManager = FileManager.default
    static let readerPageIndexCacheCapacity = 2

    /// 离线 Reader 复用当前和相邻章节的页索引；下载续传不进入此缓存。
    var readerPageIndices: [ChapterIdentity: ReaderPageIndex] = [:]
    var readerIndexAccessOrder: [ChapterIdentity] = []

    /// 资产 lease：会话读取或导出期间阻止该作品资产被删除。
    ///
    /// 以会话身份为键，一个会话最多登记一个作品：离线 Reader 打开章节时登记、会话关闭时释放；
    /// 导出任务在开始构建计划前登记、任务结束（成功／失败／取消）时释放。删除入口必须先通过
    /// `removeComicDirectory` 的 lease 门禁。
    var leasedComicsBySession: [UUID: ComicIdentity] = [:]

    /// 登记资产 lease；同一会话重复登记只保留一条。
    func acquireAssetLease(for comic: ComicIdentity, sessionID: UUID) {
        leasedComicsBySession[sessionID] = comic
    }

    /// 释放会话的资产 lease；离线 Reader 会话关闭或导出任务结束后必须调用。
    func releaseAssetLease(sessionID: UUID) {
        leasedComicsBySession.removeValue(forKey: sessionID)
    }

    /// 指定作品当前是否有活动 lease；单作品删除在改记录前用它预检。
    func hasAssetLease(for comic: ComicIdentity) -> Bool {
        isAssetLeased(sourceID: comic.sourceID.rawValue, comicID: comic.comicID)
    }

    /// 把普通图片磁盘缓存文件直接复制为本地封面资产，不把整张图片读入内存。
    ///
    /// 先复制到同目录临时文件，再替换正式路径；缓存恰好在查找后被淘汰时返回 false，调用方可改走网络下载。
    func copyCover(
        from cachedFileURL: URL,
        reference: ComicImageReference,
    ) throws -> Bool {
        let destinationURL = try DownloadAssetPaths.coverURL(for: reference)
        do {
            try copyAsset(from: cachedFileURL, to: destinationURL)
        } catch where Self.isMissingFile(error) {
            return false
        }
        return true
    }

    /// 把前台 URLSession 下载到临时文件的封面复制为正式资产，不读取或解码图片内容。
    func commitCover(
        from temporaryURL: URL,
        reference: ComicImageReference,
    ) throws {
        let destinationURL = try DownloadAssetPaths.coverURL(for: reference)
        try copyAsset(from: temporaryURL, to: destinationURL)
    }

    /// 读取本地作品封面；不访问网络。
    func readCover(for reference: ComicImageReference) throws -> Data {
        let url = try DownloadAssetPaths.coverURL(for: reference)
        return try Data(contentsOf: url)
    }

    /// 删除一个作品的整个资产目录。
    ///
    /// 用于「清理其他数据」与下载记录的用户删除入口（`DownloadManager.remove`）；用户删除时
    /// 记录已经先删成功，这里的失败只会留下孤儿目录。作品仍有 lease 时拒绝删除，
    /// 由调用方决定等待或告知用户。目录不存在时为空操作。
    func removeComicDirectory(sourceID: String, comicID: String) throws {
        guard !isAssetLeased(sourceID: sourceID, comicID: comicID) else {
            throw DownloadAssetError.assetLeased
        }

        let directory = try DownloadAssetPaths.comicDirectory(sourceID: sourceID, comicID: comicID)
        guard fileManager.fileExists(atPath: directory.path) else { return }

        try fileManager.removeItem(at: directory)
    }

    /// 作品是否有活动资产 lease（按原始字符串匹配，与删除入参一致）。
    private func isAssetLeased(sourceID: String, comicID: String) -> Bool {
        leasedComicsBySession.values.contains {
            $0.sourceID.rawValue == sourceID && $0.comicID == comicID
        }
    }

    /// 是否有任何活动 lease；设置页「清除下载记录」在停止任务前用它做门禁。
    func hasActiveAssetLease() -> Bool {
        !leasedComicsBySession.isEmpty
    }

    // MARK: - 共享文件写入

    /// 临时文件位于正式资产同一目录，完成复制后以替换/移动提交，避免内存中转图片数据。
    func copyAsset(from sourceURL: URL, to destinationURL: URL) throws {
        try fileManager.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
        )
        let temporaryURL = TemporaryFiles.makeAssetTemporaryURL(for: destinationURL)
        defer { try? fileManager.removeItem(at: temporaryURL) }

        try fileManager.copyItem(at: sourceURL, to: temporaryURL)
        try replaceOrMoveAsset(from: temporaryURL, to: destinationURL)
    }

    /// 先写同目录临时文件再替换为正式文件；崩溃只会留下 `*.tmp`，由启动清理回收。
    func writeAsset(_ data: Data, to destinationURL: URL) throws {
        try fileManager.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
        )
        let temporaryURL = TemporaryFiles.makeAssetTemporaryURL(for: destinationURL)
        defer { try? fileManager.removeItem(at: temporaryURL) }

        try data.write(to: temporaryURL)
        try replaceOrMoveAsset(from: temporaryURL, to: destinationURL)
    }

    /// 目标已存在时原子替换，首次写入时直接移动。
    private func replaceOrMoveAsset(from temporaryURL: URL, to destinationURL: URL) throws {
        if fileManager.fileExists(atPath: destinationURL.path) {
            _ = try fileManager.replaceItemAt(destinationURL, withItemAt: temporaryURL)
        } else {
            try fileManager.moveItem(at: temporaryURL, to: destinationURL)
        }
    }

    /// 缺失文件是可重下的缓存未命中；权限和其它读写错误必须向调用方传播。
    static func isMissingFile(_ error: any Error) -> Bool {
        (error as? CocoaError)?.code == .fileReadNoSuchFile
    }
}

/// 下载资产层的本地错误；不联网补图，交由上层映射。
enum DownloadAssetError: Error, Equatable, Sendable {
    /// 清单相对路径越界或非法。
    case unsafeRelativePath

    /// 章节清单缺失、字段不完整、身份不匹配或序号重复。
    case corruptedManifest

    /// 清单缺少指定页。
    case missingPage

    /// 本地资产文件存在但无法解码或已损坏（例如本地封面）。
    case corruptedAsset

    /// 资产仍被离线阅读或导出的 lease 占用，删除被拒绝；调用方应等待或告知用户。
    case assetLeased

    /// 删除入口的提示文案；其余资产错误由调用方使用自己的兜底文案。
    var removalMessage: String? {
        switch self {
        case .assetLeased:
            "有作品正在离线阅读或导出，请稍后重试"

        default:
            nil
        }
    }
}

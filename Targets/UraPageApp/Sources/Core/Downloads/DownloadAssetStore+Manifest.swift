import Foundation

// MARK: - 章节清单与页文件

extension DownloadAssetStore {
    /// 从 manifest 建立章节的页面目录；不读取或校验图片文件。
    ///
    /// Reader 只在显示具体页面时读取该页文件，避免打开章节时扫描整章图片。
    /// 空章节返回 0 页快照（阅读页显示空态）；清单缺失或损坏都按损坏报错，不当作可读章节。
    func downloadedChapter(for record: ChapterDownloadRecord) throws -> DownloadedChapterSnapshot {
        guard let manifest = try loadManifest(for: record.identity) else {
            throw DownloadAssetError.corruptedManifest
        }

        cacheReaderPageIndex(from: manifest, for: record.identity)

        let pages = manifest.pages.map { entry in
            ComicPage(
                identity: PageIdentity(chapter: record.identity, pageID: entry.pageID),
                index: entry.index,
            )
        }

        return DownloadedChapterSnapshot(
            identity: record.identity,
            title: record.title,
            order: record.order,
            totalPageCount: manifest.totalPageCount,
            pages: pages,
        )
    }

    /// 读取 manifest 指定的单页文件，不读取其它页或校验图片字节。
    ///
    /// 章节已由 SwiftData 状态限定为 `completed`；缺少 manifest 条目、文件不存在或读取失败仍会抛错。
    func readPageData(for page: ComicPage) throws -> Data {
        guard let pageIndex = try loadReaderPageIndex(for: page.identity.chapter),
              pageIndex.indices[page.identity.pageID] == page.index
        else {
            throw DownloadAssetError.missingPage
        }

        let entry = DownloadManifest.PageEntry(
            pageID: page.identity.pageID,
            index: page.index,
            relativePath: DownloadAssetPaths.pageFileName(index: page.index, pageID: page.identity.pageID),
        )
        let url = try pageDataURL(for: entry, chapter: page.identity.chapter)
        return try Data(contentsOf: url)
    }

    /// 写入一页文件并返回其清单条目；清单由调用方按批次及章节结束时原子提交。
    ///
    /// 页文件按序号与页面 ID 命名，重复写入同一页时覆盖（重试补齐路径）。
    func writePage(_ pageData: Data, for page: ComicPage) throws -> DownloadManifest.PageEntry {
        let entry = DownloadManifest.PageEntry(
            pageID: page.identity.pageID,
            index: page.index,
            relativePath: DownloadAssetPaths.pageFileName(index: page.index, pageID: page.identity.pageID),
        )
        try writeAsset(pageData, to: pageDataURL(for: entry, chapter: page.identity.chapter))
        return entry
    }

    /// 原子写入章节清单。
    func saveManifest(_ manifest: DownloadManifest, for chapter: ChapterIdentity) throws {
        try writeAsset(
            JSONEncoder().encode(manifest),
            to: DownloadAssetPaths.manifestURL(for: chapter),
        )
        if readerPageIndices[chapter] != nil {
            cacheReaderPageIndex(from: manifest, for: chapter)
        }
    }

    /// 读取指定页面条目的正式资产 URL；相对路径越界（含符号链接逃逸）或缺失时抛错（不联网补图）。
    func pageDataURL(for entry: DownloadManifest.PageEntry, chapter: ChapterIdentity) throws -> URL {
        let directory = try DownloadAssetPaths.chapterDirectory(for: chapter)
        guard !entry.relativePath.contains("/"), entry.relativePath != ".", entry.relativePath != ".." else {
            throw DownloadAssetError.unsafeRelativePath
        }

        // manifest 是磁盘外部输入：解析符号链接后再校验 containment，拒绝越界。
        let url = directory.appending(path: entry.relativePath, directoryHint: .notDirectory)
            .resolvingSymlinksInPath()
        guard DownloadAssetPaths.isContained(url, in: directory.resolvingSymlinksInPath()) else {
            throw DownloadAssetError.unsafeRelativePath
        }

        return url
    }

    // MARK: - 清单读取与索引缓存

    func loadReaderPageIndex(for chapter: ChapterIdentity) throws -> ReaderPageIndex? {
        if let pageIndex = readerPageIndices[chapter] {
            touchReaderIndex(chapter)
            return pageIndex
        }

        guard let manifest = try loadManifest(for: chapter) else { return nil }

        cacheReaderPageIndex(from: manifest, for: chapter)
        return readerPageIndices[chapter]
    }

    /// 读取指定章节的清单；不存在时返回 `nil`，内容损坏或身份不匹配时抛错。
    ///
    /// 清单读取不经过页索引缓存：续传与导出需要完整清单，缓存只服务 Reader 的单页定位。
    func loadManifest(for chapter: ChapterIdentity) throws -> DownloadManifest? {
        let url = try DownloadAssetPaths.manifestURL(for: chapter)
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch where Self.isMissingFile(error) {
            return nil
        }

        let manifest: DownloadManifest
        do {
            manifest = try JSONDecoder().decode(DownloadManifest.self, from: data)
        } catch {
            throw DownloadAssetError.corruptedManifest
        }
        try validate(manifest, for: chapter)
        return manifest
    }

    /// 章节清单来自磁盘输入；身份、页序号和条目唯一性必须与请求章节一致。
    private func validate(_ manifest: DownloadManifest, for chapter: ChapterIdentity) throws {
        guard manifest.chapterID == chapter.chapterID,
              manifest.totalPageCount >= 0
        else {
            throw DownloadAssetError.corruptedManifest
        }

        var indices: Set<Int> = []
        var pageIDs: Set<String> = []
        for entry in manifest.pages {
            guard (0 ..< manifest.totalPageCount).contains(entry.index),
                  !entry.pageID.isEmpty,
                  entry.relativePath == DownloadAssetPaths.pageFileName(
                      index: entry.index,
                      pageID: entry.pageID,
                  ),
                  indices.insert(entry.index).inserted,
                  pageIDs.insert(entry.pageID).inserted
            else {
                throw DownloadAssetError.corruptedManifest
            }
        }
    }

    private func cacheReaderPageIndex(from manifest: DownloadManifest, for chapter: ChapterIdentity) {
        readerPageIndices[chapter] = ReaderPageIndex(
            indices: Dictionary(uniqueKeysWithValues: manifest.pages.map { ($0.pageID, $0.index) }),
        )
        touchReaderIndex(chapter)

        if readerIndexAccessOrder.count > Self.readerPageIndexCacheCapacity {
            let evictedChapter = readerIndexAccessOrder.removeFirst()
            readerPageIndices[evictedChapter] = nil
        }
    }

    private func touchReaderIndex(_ chapter: ChapterIdentity) {
        readerIndexAccessOrder.removeAll { $0 == chapter }
        readerIndexAccessOrder.append(chapter)
    }
}

/// 离线 Reader 的页索引：pageID → 章节内序号。
struct ReaderPageIndex {
    let indices: [String: Int]
}

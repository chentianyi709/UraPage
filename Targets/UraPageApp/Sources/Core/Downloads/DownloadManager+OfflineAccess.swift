import Foundation

// MARK: - 离线读取与资产 lease

extension DownloadManager {
    /// 打开本地章节并登记离线读取 lease；Reader 会话关闭时由 `releaseDownloadedAssetLease` 释放。
    ///
    /// 没有已完成记录是无效身份；记录已完成但清单缺失／损坏按本地资产损坏报错，
    /// 与「完成即数据完整」的约定一致，不伪装成身份问题。
    func openDownloadedChapter(
        _ identity: ChapterIdentity,
        readerSessionID: UUID,
    ) async throws -> any SourceOpenedChapter {
        guard let record = try await persistence().chapterRecord(for: identity),
              record.state == .completed
        else {
            throw ComicSourceError.invalidIdentity
        }

        await assetStore.acquireAssetLease(for: identity.comic, sessionID: readerSessionID)
        return try await DownloadedSourceChapter(assetStore.downloadedChapter(for: record))
    }

    /// 释放离线读取 lease；由 `ReaderDownloadedContent.close` 在会话内容任务结束后调用。
    func releaseDownloadedAssetLease(readerSessionID: UUID) async {
        await assetStore.releaseAssetLease(sessionID: readerSessionID)
    }

    /// 登记导出的资产 lease：导出期间阻止「清除下载记录」与单作品删除移除正在读取的文件。
    func acquireExportAssetLease(for comic: ComicIdentity, sessionID: UUID) async {
        await assetStore.acquireAssetLease(for: comic, sessionID: sessionID)
    }

    /// 释放导出的资产 lease；导出成功、失败或取消后都必须调用。
    func releaseExportAssetLease(sessionID: UUID) async {
        await assetStore.releaseAssetLease(sessionID: sessionID)
    }

    /// 读取一个已经下载并经过来源处理的本地页面；不访问网络或 Reader 在线缓存。
    func downloadedPagePayload(for page: ComicPage) async throws -> SourcePagePayload {
        try await .encoded(assetStore.readPageData(for: page))
    }
}

/// 离线 Reader 的章节句柄只暴露 manifest 中登记的页面，不包含网络请求能力。
private struct DownloadedSourceChapter: SourceOpenedChapter {
    let content: SourceChapterContent

    init(_ chapter: DownloadedChapterSnapshot) {
        content = SourceChapterContent(
            identity: chapter.identity,
            title: chapter.title,
            pages: chapter.pages,
            totalPageCount: chapter.totalPageCount,
        )
    }

    /// 本地章节按 manifest 直接列出页面，没有接口分页。
    var pageBatchSize: Int? {
        nil
    }

    func pages(containing index: Int) async throws -> [ComicPage] {
        content.pages.filter { $0.index == index }
    }

    func downloadPage(_ page: ComicPage, to fileURL: URL) async throws {
        throw ComicSourceError.invalidIdentity
    }

    func pagePayload(for page: ComicPage, from fileURL: URL) async throws -> SourcePagePayload {
        throw ComicSourceError.invalidIdentity
    }
}

import Foundation

// MARK: - 章节页传输

extension DownloadManager {
    /// 缓存优先取得来源载荷；Reader 与作品下载使用同一入口和同一前台页传输。
    ///
    /// Reader 在调用时读取来源当前 Host 代次；Host 切换后新请求不会加入旧线路的在途传输。
    /// `consume` 在并发执行器运行（见 `PageTransferCoordinator.withPagePayload`），
    /// 消费者可以放心在这里做解扰后的编码与写盘。
    func withPagePayload<Result: Sendable>(
        for page: ComicPage,
        using handle: any SourceOpenedChapter,
        consume: @concurrent @Sendable (SourcePagePayload) async throws -> Result,
    ) async throws -> Result {
        try await withPagePayload(
            for: page,
            using: handle,
            hostGeneration: hostGenerations[page.identity.chapter.comic.sourceID, default: 0],
            consume: consume,
        )
    }

    /// 使用调用方捕获的 Host 代次取得载荷；作品下载在章节开始前固定代次，旧 run 不会复用新 run 的传输。
    func withPagePayload<Result: Sendable>(
        for page: ComicPage,
        using handle: any SourceOpenedChapter,
        hostGeneration: UInt64,
        consume: @concurrent @Sendable (SourcePagePayload) async throws -> Result,
    ) async throws -> Result {
        try await transfers.withPagePayload(
            for: page,
            using: handle,
            hostGeneration: hostGeneration,
            consume: consume,
        )
    }
}

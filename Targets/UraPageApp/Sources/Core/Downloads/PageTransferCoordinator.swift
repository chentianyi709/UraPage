import Foundation

/// Reader 与作品下载共用缓存优先的前台章节页传输。
/// Reader 只调用当前可见／预加载范围内的页面；作品下载按章节清单逐页调度。
actor PageTransferCoordinator {
    /// 合并键包含来源 Host 代次：切换线路后新请求不能加入旧线路仍在途的传输。
    private struct TransferKey: Hashable {
        let page: PageIdentity
        let hostGeneration: UInt64
    }

    private struct PageTransfer {
        let id: UUID
        let task: Task<Void, Never>
        var waiters: [UUID: CheckedContinuation<SourcePagePayload, any Error>]
    }

    let cacheReading: any ChapterImageCacheReading
    private var pageTransfers: [TransferKey: PageTransfer] = [:]

    init(cacheReading: any ChapterImageCacheReading) {
        self.cacheReading = cacheReading
    }

    /// 先读 Reader 磁盘缓存；未命中时合并同页在途请求，再把载荷交给当前消费者。
    ///
    /// `consume` 标 `@concurrent`：消费者在并发执行器上完成解码／编码／写盘，不占用本 actor，
    /// 否则读缓存命中（Reader 也在走这条入口）会被其它页的处理阻塞。
    func withPagePayload<Result: Sendable>(
        for page: ComicPage,
        using handle: any SourceOpenedChapter,
        hostGeneration: UInt64,
        consume: @concurrent @Sendable (SourcePagePayload) async throws -> Result,
    ) async throws -> Result {
        try Task.checkCancellation()
        if let cachedData = try await cacheReading.cachedPageData(for: page.identity) {
            try Task.checkCancellation()
            return try await consume(.encoded(cachedData))
        }

        let payload = try await transferredPayload(
            for: page,
            using: handle,
            hostGeneration: hostGeneration,
        )
        try Task.checkCancellation()
        return try await consume(payload)
    }

    /// 每个等待者独立取消；底层前台请求在最后一个等待者退出时取消。
    private func transferredPayload(
        for page: ComicPage,
        using handle: any SourceOpenedChapter,
        hostGeneration: UInt64,
    ) async throws -> SourcePagePayload {
        let waiterID = UUID()
        let key = TransferKey(page: page.identity, hostGeneration: hostGeneration)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard !Task.isCancelled else {
                    continuation.resume(throwing: CancellationError())
                    return
                }

                if var transfer = pageTransfers[key] {
                    transfer.waiters[waiterID] = continuation
                    pageTransfers[key] = transfer
                    return
                }

                let transferID = UUID()
                let task = Task { [weak self] in
                    let result: Result<SourcePagePayload, any Error>
                    do {
                        result = try await .success(Self.downloadPayload(for: page, using: handle))
                    } catch {
                        result = .failure(error)
                    }
                    await self?.finishTransfer(for: key, id: transferID, result: result)
                }
                pageTransfers[key] = PageTransfer(
                    id: transferID,
                    task: task,
                    waiters: [waiterID: continuation],
                )
            }
        } onCancel: {
            Task { await self.cancelWaiter(for: key, id: waiterID) }
        }
    }

    private func finishTransfer(
        for key: TransferKey,
        id: UUID,
        result: Result<SourcePagePayload, any Error>,
    ) {
        guard let transfer = pageTransfers[key], transfer.id == id else { return }

        pageTransfers[key] = nil
        for continuation in transfer.waiters.values {
            continuation.resume(with: result)
        }
    }

    private func cancelWaiter(for key: TransferKey, id waiterID: UUID) {
        guard var transfer = pageTransfers[key],
              let continuation = transfer.waiters.removeValue(forKey: waiterID)
        else {
            return
        }

        if transfer.waiters.isEmpty {
            pageTransfers[key] = nil
            transfer.task.cancel()
        } else {
            pageTransfers[key] = transfer
        }
        continuation.resume(throwing: CancellationError())
    }

    /// 网络下载、来源解扰和临时文件操作都在并发执行器运行。
    @concurrent
    private static func downloadPayload(
        for page: ComicPage,
        using handle: any SourceOpenedChapter,
    ) async throws -> SourcePagePayload {
        let fileURL = TemporaryFiles.makePageTransferURL()
        defer { try? FileManager.default.removeItem(at: fileURL) }

        try await handle.downloadPage(page, to: fileURL)
        try Task.checkCancellation()
        return try await handle.pagePayload(for: page, from: fileURL)
    }
}

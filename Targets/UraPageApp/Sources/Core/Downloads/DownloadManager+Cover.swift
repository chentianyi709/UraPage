import Foundation

// MARK: - 作品封面处理

extension DownloadManager {
    /// 立即启动作品的封面任务；入队、继续／重试与启动对账都走这里。
    ///
    /// 封面与作品调度相互独立：不占每来源作品名额、不等待作品真正开始；作品处于等待中时封面照常处理。
    /// 已有在途封面任务、作品被暂停或没有待处理封面时直接返回。
    func startCoverTransfer(_ comic: ComicIdentity) async {
        guard coverRuns[comic] == nil, !pausedWorks.contains(comic) else { return }

        let transfer: PendingCoverTransfer?
        do {
            transfer = try await persistence().pendingCoverTransfer(for: comic)
        } catch {
            AppLogger.warning(
                "下载封面引用读取失败，source=\(comic.sourceID.rawValue)，errorType=\(String(reflecting: type(of: error)))",
                category: "App.Download",
            )
            return
        }
        guard let transfer, coverRuns[comic] == nil, !pausedWorks.contains(comic) else { return }

        let token = UUID()
        let task = Task { await self.runCoverTransfer(transfer, token: token) }
        coverRuns[comic] = CoverRunState(token: token, task: task)
    }

    private func runCoverTransfer(_ transfer: PendingCoverTransfer, token: UUID) async {
        await downloadCover(transfer, token: token)

        let comic = transfer.identity
        if coverRuns[comic]?.token == token {
            coverRuns[comic] = nil
        }
    }

    /// 处理当前作品的封面资源；缓存命中直接复制本地文件，未命中才用普通前台 URLSession 下载。
    ///
    /// 不把文件读入 `Data`、不验证或解码字节；成功／失败都按封面自身状态广播，
    /// 作品章节任务可能已经结束（运行时已释放），因此广播按持久化重建该作品 summary。
    func downloadCover(_ transfer: PendingCoverTransfer, token: UUID) async {
        guard case let .remote(reference) = transfer.cover else { return }

        let comic = transfer.identity

        do {
            guard isCurrentCoverRun(comic, token: token),
                  try await persistence().startCover(for: comic, now: Date())
            else { return }

            await publishCoverChange(comic: comic, state: .downloading)

            let imageService = catalog.runtime(for: comic.sourceID).makeBrowsingImages()
            let resource = try imageService.resource(for: reference)
            let cachedFileURL = try await browsingImageCache.cachedOriginalFile(for: resource)
            guard isCurrentCoverRun(comic, token: token) else { return }

            let copiedFromCache: Bool
            if let cachedFileURL {
                copiedFromCache = try await assetStore.copyCover(
                    from: cachedFileURL,
                    reference: reference,
                )
            } else {
                copiedFromCache = false
            }

            if !copiedFromCache {
                let request = try await imageService.request(for: resource)
                let temporaryURL = try await Self.downloadCoverFile(for: request)
                defer { try? FileManager.default.removeItem(at: temporaryURL) }

                guard isCurrentCoverRun(comic, token: token) else { return }

                try await assetStore.commitCover(
                    from: temporaryURL,
                    reference: reference,
                )
            }
            guard isCurrentCoverRun(comic, token: token) else { return }

            let saved = try await persistence().saveCoverAsset(
                expectedCover: transfer.cover,
                for: comic,
                now: Date(),
            )
            guard saved else {
                await markCoverFailed(for: comic, expectedCover: transfer.cover, token: token)
                return
            }

            await publishCoverChange(
                comic: comic,
                cover: .downloaded(reference: reference),
                state: .completed,
            )
        } catch {
            guard !Task.isCancelled else { return }

            await markCoverFailed(for: comic, expectedCover: transfer.cover, token: token)
            AppLogger.warning(
                "作品封面处理失败，source=\(comic.sourceID.rawValue)，errorType=\(String(reflecting: type(of: error)))",
                category: "App.Download",
            )
        }
    }

    private func markCoverFailed(
        for comic: ComicIdentity,
        expectedCover: ComicImageSource,
        token: UUID,
    ) async {
        guard isCurrentCoverRun(comic, token: token) else { return }

        do {
            guard try await persistence().failCover(
                for: comic,
                expectedCover: expectedCover,
                now: Date(),
            ) else { return }
        } catch {
            AppLogger.error(
                "封面失败状态写入失败，source=\(comic.sourceID.rawValue)，errorType=\(String(reflecting: type(of: error)))",
                category: "App.Download",
            )
        }
        guard isCurrentCoverRun(comic, token: token) else { return }

        await publishCoverChange(comic: comic, state: .failed)
    }

    /// 本次封面任务是否仍是当前 owner：未被取消、未被暂停、也未被更新的封面任务接管。
    ///
    /// 封面任务与作品章节任务相互独立，`await` 之后必须重新确认归属，否则旧任务会改写新任务的封面状态。
    private func isCurrentCoverRun(_ comic: ComicIdentity, token: UUID) -> Bool {
        !Task.isCancelled
            && !isRunStopped(comic)
            && coverRuns[comic]?.token == token
    }

    /// 更新封面的运行时状态（作品正在运行时），并按持久化重建该作品 summary 后广播。
    private func publishCoverChange(
        comic: ComicIdentity,
        cover: ComicImageSource? = nil,
        state: DownloadState,
    ) async {
        if var runtime = runtimes[comic] {
            if let cover {
                runtime.cover = cover
            }
            runtime.coverState = state
            runtimes[comic] = runtime
        }

        do {
            let summary = try await summary(for: comic)
            publishStructural(progress: summary)
        } catch {
            // 封面状态已写入内存；持久化投影读取失败时仍广播一次结构变化，
            // 让列表按持久化重建，而不是把失败当成“没有作品”。
            AppLogger.error(
                "封面状态广播时读取作品状态失败，source=\(comic.sourceID.rawValue)，errorType=\(String(reflecting: type(of: error)))",
                category: "App.Download",
            )
            publishStructural()
        }
    }

    /// 使用普通前台 URLSession 下载封面到系统临时文件。
    @concurrent
    private static func downloadCoverFile(for request: URLRequest) async throws -> URL {
        let (fileURL, response) = try await URLSession.shared.download(for: request)
        guard let response = response as? HTTPURLResponse,
              (200 ..< 300).contains(response.statusCode)
        else {
            try? FileManager.default.removeItem(at: fileURL)
            let statusCode = (response as? HTTPURLResponse)?.statusCode
            throw ComicSourceError.serverRejected(code: statusCode.map(String.init) ?? "unknown")
        }

        return fileURL
    }
}

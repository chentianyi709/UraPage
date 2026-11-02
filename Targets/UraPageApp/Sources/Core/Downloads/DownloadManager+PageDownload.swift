import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - 页面下载与提交

extension DownloadManager {
    /// 以受控并发下载一组页面；每页落盘后立即记入章节清单，并按节流提交。
    ///
    /// 每页成功落盘算一个完成单位；运行停止后不再派出新页，等待在途页结束。
    /// `hostGeneration` 在章节开始时固定，页传输只与同代次请求合并在途任务。
    /// 返回更新后的清单提交状态与是否出现失败页。
    func downloadPages(
        _ pages: [ComicPage],
        handle: any SourceOpenedChapter,
        comic: ComicIdentity,
        chapterIndex: Int,
        hostGeneration: UInt64,
        commit: ChapterManifestCommit,
    ) async -> (commit: ChapterManifestCommit, hadFailure: Bool) {
        var hadFailure = false

        let commitState = await withTaskGroup(of: DownloadManifest.PageEntry?.self) { group in
            var commitState = commit
            var next = 0
            var active = 0

            while active < pageConcurrencyPerWork, next < pages.count {
                let page = pages[next]
                next += 1
                active += 1
                group.addTask {
                    // 全局名额压住「作品数 × 页并发」的乘积；取消时退出等待，不占用名额。
                    guard await self.pageBudget.acquire() else { return nil }

                    let entry = await self.processPage(page, handle: handle, hostGeneration: hostGeneration)
                    await self.pageBudget.release()
                    return entry
                }
            }

            while active > 0 {
                guard let entry = await group.next() else { break }

                active -= 1

                if let entry {
                    _ = advanceChapterUnit(comic: comic, index: chapterIndex)
                    commitState.record(entry)
                    // 每页落盘后按节流提交：意外终止最多丢在途页与最后未提交的少数页。
                    commitState = await commitManifest(
                        commitState,
                        identity: handle.content.identity,
                        totalPageCount: handle.content.totalPageCount,
                        force: false,
                    )
                } else if !isRunStopped(comic) {
                    hadFailure = true
                }

                if !isRunStopped(comic) {
                    while active < pageConcurrencyPerWork, next < pages.count {
                        let page = pages[next]
                        next += 1
                        active += 1
                        group.addTask {
                            // 全局名额压住「作品数 × 页并发」的乘积；取消时退出等待，不占用名额。
                            guard await self.pageBudget.acquire() else { return nil }

                            let entry = await self.processPage(
                                page,
                                handle: handle,
                                hostGeneration: hostGeneration,
                            )
                            await self.pageBudget.release()
                            return entry
                        }
                    }
                }
            }

            return commitState
        }

        return (commitState, hadFailure)
    }

    /// 按节流提交章节清单；批次边界与章节结束由调用方传 `force`。
    ///
    /// 提交失败只保留未提交状态，交给下一个提交点重试，章节结束按 `isFullyCommitted` 判定。
    func commitManifest(
        _ commit: ChapterManifestCommit,
        identity: ChapterIdentity,
        totalPageCount: Int,
        force: Bool,
    ) async -> ChapterManifestCommit {
        guard commit.shouldCommit(force: force) else { return commit }

        var updated = commit
        if await saveManifest(
            identity: identity,
            totalPageCount: totalPageCount,
            entries: commit.entries,
        ) {
            updated.markCommitted()
        }

        return updated
    }

    /// 原子写入章节清单；失败只记录并返回 `false`，由调用方决定章节是否算完成。
    func saveManifest(
        identity: ChapterIdentity,
        totalPageCount: Int,
        entries: [String: DownloadManifest.PageEntry],
    ) async -> Bool {
        let manifest = DownloadManifest(
            chapterID: identity.chapterID,
            totalPageCount: totalPageCount,
            pages: entries.values.sorted { $0.index < $1.index },
        )

        do {
            try await assetStore.saveManifest(manifest, for: identity)
            return true
        } catch {
            AppLogger.error(
                "下载章节清单写入失败，chapterID=\(identity.chapterID)，errorType=\(String(reflecting: type(of: error)))",
                category: "App.Download",
            )
            return false
        }
    }

    // MARK: - 单页

    /// 前台下载、编码并落盘单页；页面缓存、Reader 与下载队列共用同一页面载荷入口。
    ///
    /// 单页失败自动重试（仅可重试错误）；仍失败返回 `nil`，由上层标记章节为部分失败。
    /// 重试不改变单位计数：一页只计一个单位，成功才计入。
    /// 同页在途请求由共享传输 owner 按 Host 代次合并；载荷处理完后临时文件立即清理。
    @concurrent
    private nonisolated func processPage(
        _ page: ComicPage,
        handle: any SourceOpenedChapter,
        hostGeneration: UInt64,
    ) async -> DownloadManifest.PageEntry? {
        let maxAttempts = 3
        var lastError: (any Error)?

        for attempt in 1 ... maxAttempts {
            if Task.isCancelled {
                return nil
            }

            do {
                return try await withPagePayload(
                    for: page,
                    using: handle,
                    hostGeneration: hostGeneration,
                ) { payload in
                    let data = try Self.encode(payload)
                    return try await self.assetStore.writePage(data, for: page)
                }
            } catch is CancellationError {
                return nil
            } catch {
                lastError = error
                guard Self.isRetryable(error), attempt < maxAttempts else {
                    break
                }

                // 短暂退避重试；取消在这里会直接抛出并结束。
                do {
                    try await Task.sleep(for: .milliseconds(300 * attempt))
                } catch {
                    return nil
                }
            }
        }

        AppLogger.warning(
            "下载页面失败，comicID=\(page.identity.chapter.comic.comicID)，chapterID=\(page.identity.chapter.chapterID)，page=\(page.index)，errorType=\(String(reflecting: type(of: lastError ?? ComicSourceError.invalidResponse)))",
            category: "App.Download",
        )
        return nil
    }

    /// 单页失败是否值得自动重试：取消交给上层结束，本地资产损坏重试不会改变结果，
    /// 其余失败（网络、超时、认证、来源内容）都允许短退避重试。
    private static func isRetryable(_ error: any Error) -> Bool {
        if error is CancellationError || error is DownloadAssetError {
            return false
        }

        return true
    }

    /// 把来源载荷转成可落盘的编码字节；解扰位图按无损 PNG 编码保存。
    private static func encode(_ payload: SourcePagePayload) throws -> Data {
        switch payload {
        case let .encoded(data):
            return data

        case let .decoded(image):
            let data = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(
                data,
                UTType.png.identifier as CFString,
                1,
                nil,
            ) else {
                throw ComicSourceError.invalidResponse
            }

            CGImageDestinationAddImage(destination, image, nil)
            guard CGImageDestinationFinalize(destination) else {
                throw ComicSourceError.invalidResponse
            }

            return data as Data
        }
    }
}


extension ComicReaderViewModel {
    /// 区分首次进入和菜单切章的展示状态。
    private enum ChapterRequestPurpose {
        case initial
        case menuSwitch
    }

    /// 只在当前 Reader 尚未请求时加载入口章节。
    func loadIfNeeded() {
        guard loadState == .idle, loadTask == nil else {
            return
        }

        startChapterRequest(
            input.initialChapterIdentity,
            purpose: .initial,
        )
    }

    /// 重新加载入口章节，仅供首次加载失败页使用。
    func retry() {
        startChapterRequest(
            input.initialChapterIdentity,
            purpose: .initial,
        )
    }

    /// Toast 已提示后消费一次性切章失败状态。
    func consumeChapterSwitchFailure() {
        guard chapterSwitchState == .failed else {
            return
        }

        chapterSwitchState = .idle
    }

    /// ReaderSession 关闭时同步取消章节请求，并把任务交给统一 close 屏障等待。
    func cancelContentWork() -> [Task<Void, Never>] {
        loadGeneration &+= 1
        cancelCurrentRequests()
        chapterRequests.values.forEach { $0.task.cancel() }
        return taskRetirement.drain()
    }

    /// Canvas 页面任务全部结束后再释放来源章节句柄和展示内容。
    func closeContentResources() async throws {
        openedChapters.removeAll()
        chapterRequests.removeAll()
        clearActiveContent()
        loadState = .idle
        await downloadedContent?.close()
    }

    /// 从通用章节菜单切换到输入中的指定章节。
    func selectChapter(_ chapterIdentity: ChapterIdentity) {
        guard chapterIndexByID[chapterIdentity] != nil else {
            return
        }

        if currentPage?.identity.chapter == chapterIdentity {
            discardPendingChapterSwitch()
            chapterSwitchState = .idle
            return
        }
        guard chapterSwitchState.loadingChapterIdentity != chapterIdentity else {
            return
        }

        startChapterRequest(chapterIdentity, purpose: .menuSwitch)
    }

    /// 回到当前章／跳页代表放弃未完成的切章意图，但保留其请求继续缓存。
    func discardPendingChapterSwitch() {
        guard chapterSwitchState.loadingChapterIdentity != nil else { return }

        retireCurrentRequests()
        loadGeneration += 1
        chapterSwitchState = .idle
    }

    /// 创建当前页面拥有的章节请求。
    private func startChapterRequest(
        _ chapterIdentity: ChapterIdentity,
        purpose: ChapterRequestPurpose,
    ) {
        guard let targetChapterIndex = chapterIndexByID[chapterIdentity] else { return }

        let reference = input.chapters[targetChapterIndex]
        retireCurrentRequests()
        loadGeneration += 1
        let generation = loadGeneration
        let input = input

        switch purpose {
        case .initial:
            clearActiveContent()
            loadState = .loading

        case .menuSwitch:
            chapterSwitchState = .loading(chapterIdentity)
        }

        if let openedChapter = openedChapters[chapterIdentity] {
            AppLogger.debug(
                "复用已打开章节，chapterID=\(chapterIdentity.chapterID)，generation=\(generation)",
                category: "Reader.Chapter",
            )
            activateChapter(
                openedChapter,
                chapterIndex: targetChapterIndex,
                generation: generation,
                initialPage: openedChapter.slots.first,
            )
            return
        }

        AppLogger.debug(
            "开始加载章节，comicID=\(input.comicIdentity.comicID)，chapterID=\(chapterIdentity.chapterID)，generation=\(generation)",
            category: "Reader.Chapter",
        )
        loadTask = Task { [weak self] in
            guard let self else { return }

            do {
                let openedChapter = try await openChapterIfNeeded(reference.identity)
                try Task.checkCancellation()

                let startPosition: ReaderStartPosition? = switch purpose {
                case .initial:
                    input.startPosition
                case .menuSwitch:
                    nil
                }
                let initialPage = await ReaderPageSlots.initialPage(
                    in: openedChapter.slots,
                    content: openedChapter.content,
                    startPosition: startPosition,
                )
                try Task.checkCancellation()
                activateChapter(
                    openedChapter,
                    chapterIndex: targetChapterIndex,
                    generation: generation,
                    initialPage: initialPage,
                )
            } catch is CancellationError {
                finishChapterCancellation(
                    generation: generation,
                    purpose: purpose,
                )
            } catch let error as ComicSourceError {
                finishChapterFailure(
                    SourceLoadDisplayError(error),
                    chapterIdentity: chapterIdentity,
                    generation: generation,
                    purpose: purpose,
                )
            } catch {
                finishChapterFailure(
                    .unavailable,
                    chapterIdentity: chapterIdentity,
                    generation: generation,
                    purpose: purpose,
                )
            }
        }
    }

    /// 首批请求按章节共享；旧展示意图失效不影响缓存，新章也不等待其它章节。
    func openChapterIfNeeded(_ identity: ChapterIdentity) async throws -> ReaderOpenedChapter {
        try Task.checkCancellation()
        if let opened = openedChapters[identity] {
            return opened
        }

        let request: ReaderChapterRequest
        if let existing = chapterRequests[identity] {
            request = existing
        } else {
            let openChapter = openChapter
            request = ReaderChapterRequest(task: Task { @concurrent in
                let source = try await openChapter(identity)
                try Task.checkCancellation()
                guard source.content.identity == identity else {
                    throw ComicSourceError.invalidResponse
                }

                let slots = try await ReaderPageSlots.prepare(content: source.content)
                return ReaderOpenedChapter(source: source, slots: slots)
            })
            chapterRequests[identity] = request
        }
        defer {
            // 失败后可立即重试；旧等待者不能清除后来创建的同章请求。
            if chapterRequests[identity]?.id == request.id {
                chapterRequests[identity] = nil
            }
        }
        let opened = try await request.task.value
        try Task.checkCancellation()
        openedChapters[identity] = opened
        return opened
    }

    /// 用一章已打开内容替换 Canvas，并重置连续章节窗口。
    private func activateChapter(
        _ openedChapter: ReaderOpenedChapter,
        chapterIndex: Int,
        generation: Int,
        initialPage: ReaderPageSlot?,
    ) {
        guard generation == loadGeneration else {
            return
        }

        let chapter = openedChapter.content
        chapters = [chapter]
        replacePages(openedChapter.slots)
        currentPage = initialPage
        if let initialPage,
           initialPage.identity != openedChapter.slots.first?.identity {
            scrollRequestSerial &+= 1
            scrollRequest = ReaderCanvasScrollRequest(
                id: scrollRequestSerial,
                pageID: initialPage.identity,
            )
        } else {
            scrollRequest = nil
        }
        earliestChapterIndex = chapterIndex
        latestChapterIndex = chapterIndex
        chapterSwitchState = .idle
        loadState = .loaded
        loadTask = nil
        AppLogger.info(
            "章节加载完成，chapterID=\(chapter.identity.chapterID)，chapterIndex=\(chapterIndex)，pages=\(chapter.pages.count)",
            category: "Reader.Chapter",
        )
    }

    /// 页面退出或新请求取代旧请求时不展示错误。
    private func finishChapterCancellation(
        generation: Int,
        purpose: ChapterRequestPurpose,
    ) {
        guard generation == loadGeneration else {
            return
        }

        switch purpose {
        case .initial:
            clearActiveContent()
            loadState = .idle

        case .menuSwitch:
            chapterSwitchState = .idle
        }
        loadTask = nil
    }

    /// 首次加载失败展示整页错误，菜单切章失败保留原内容。
    private func finishChapterFailure(
        _ error: SourceLoadDisplayError,
        chapterIdentity: ChapterIdentity,
        generation: Int,
        purpose: ChapterRequestPurpose,
    ) {
        guard generation == loadGeneration else {
            return
        }

        switch purpose {
        case .initial:
            clearActiveContent()
            loadState = .failed(error)

        case .menuSwitch:
            chapterSwitchState = .failed
        }
        loadTask = nil
        AppLogger.error(
            "章节加载失败，chapterID=\(chapterIdentity.chapterID)，error=\(String(describing: error))",
            category: "Reader.Chapter",
        )
    }

    /// 切章只解绑展示任务，旧请求继续缓存；关闭时仍统一取消、等待退出。
    private func retireCurrentRequests() {
        taskRetirement.retain([loadTask, previousChapterTask, nextChapterTask].compactMap(\.self))
        clearCurrentRequests()
    }

    /// 退出时取消当前展示任务，并由 generation 拒绝迟到的展示结果。
    func cancelCurrentRequests() {
        taskRetirement.cancel([loadTask, previousChapterTask, nextChapterTask].compactMap(\.self))
        clearCurrentRequests()
    }

    private func clearCurrentRequests() {
        loadTask = nil
        previousChapterTask = nil
        nextChapterTask = nil
        previousChapterLoadState = .idle
        nextChapterLoadState = .idle
    }

    /// 清除当前 Canvas 窗口，保留 Reader 生命周期内已打开章节。
    private func clearActiveContent() {
        chapters = []
        replacePages([])
        currentPage = nil
        scrollRequest = nil
        chapterSwitchState = .idle
        previousChapterLoadState = .idle
        nextChapterLoadState = .idle
        earliestChapterIndex = nil
        latestChapterIndex = nil
    }
}

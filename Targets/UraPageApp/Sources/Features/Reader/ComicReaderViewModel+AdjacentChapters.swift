
extension ComicReaderViewModel {
    /// 两个方向共享请求与错误处理，只在索引和页面插入位置上区分。
    @MainActor
    private enum AdjacentDirection {
        case previous
        case next

        var state: ReferenceWritableKeyPath<
            ComicReaderViewModel,
            ReaderAdjacentChapterLoadState,
        > {
            self == .previous ? \.previousChapterLoadState : \.nextChapterLoadState
        }

        var task: ReferenceWritableKeyPath<ComicReaderViewModel, Task<Void, Never>?> {
            self == .previous ? \.previousChapterTask : \.nextChapterTask
        }
    }

    func loadPreviousChapterIfNeeded() {
        loadAdjacentChapter(.previous)
    }

    func loadNextChapterIfNeeded() {
        loadAdjacentChapter(.next)
    }

    func retryPreviousChapter() {
        retryAdjacentChapter(.previous)
    }

    func retryNextChapter() {
        retryAdjacentChapter(.next)
    }

    private func retryAdjacentChapter(_ direction: AdjacentDirection) {
        guard self[keyPath: direction.state] == .failed else { return }

        self[keyPath: direction.state] = .idle
        loadAdjacentChapter(direction)
    }

    private func loadAdjacentChapter(_ direction: AdjacentDirection) {
        guard loadState == .loaded,
              self[keyPath: direction.state] == .idle,
              self[keyPath: direction.task] == nil,
              let boundary = direction == .previous ? earliestChapterIndex : latestChapterIndex
        else { return }

        let index = boundary + (direction == .previous ? -1 : 1)
        guard input.chapters.indices.contains(index) else { return }

        let reference = input.chapters[index]
        let generation = loadGeneration
        self[keyPath: direction.state] = .loading

        if let opened = openedChapters[reference.identity] {
            finishAdjacentChapter(opened, at: index, direction: direction, generation: generation)
            return
        }

        self[keyPath: direction.task] = Task { [weak self] in
            guard let self else { return }

            do {
                let opened = try await openChapterIfNeeded(reference.identity)
                try Task.checkCancellation()
                finishAdjacentChapter(
                    opened,
                    at: index,
                    direction: direction,
                    generation: generation,
                )
            } catch is CancellationError {
                finishAdjacentRequest(direction, state: .idle, generation: generation)
            } catch {
                finishAdjacentRequest(direction, state: .failed, generation: generation)
                AppLogger.error(
                    "相邻章节加载失败，direction=\(direction)，errorType=\(type(of: error))",
                    category: "Reader.Chapter",
                )
            }
        }
    }

    /// 每个方向只有一个请求；generation 有效时，结果必定属于当前窗口的相邻位置。
    private func finishAdjacentChapter(
        _ opened: ReaderOpenedChapter,
        at index: Int,
        direction: AdjacentDirection,
        generation: Int,
    ) {
        guard generation == loadGeneration else { return }

        let chapter = opened.content
        openedChapters[chapter.identity] = opened
        switch direction {
        case .previous:
            earliestChapterIndex = index
            chapters.insert(chapter, at: 0)
            prependPages(opened.slots)

        case .next:
            latestChapterIndex = index
            chapters.append(chapter)
            appendPages(opened.slots)
        }
        finishAdjacentRequest(direction, state: .idle, generation: generation)
        AppLogger.info(
            "相邻章节已加载，direction=\(direction)，chapterIndex=\(index)，pages=\(chapter.pages.count)",
            category: "Reader.Chapter",
        )
    }

    /// 取消也恢复 idle，避免只清任务却永久显示边界加载占位。
    private func finishAdjacentRequest(
        _ direction: AdjacentDirection,
        state: ReaderAdjacentChapterLoadState,
        generation: Int,
    ) {
        guard generation == loadGeneration else { return }

        self[keyPath: direction.task] = nil
        self[keyPath: direction.state] = state
    }
}

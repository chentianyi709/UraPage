import Foundation

extension ComicReaderViewModel {
    /// 使用已打开章节映射返回指定章节内容。
    func chapterContent(
        for chapterIdentity: ChapterIdentity,
    ) -> SourceChapterContent? {
        openedChapters[chapterIdentity]?.content
    }

    /// 接收 Canvas 判定的主可见页。
    func updateCurrentPage(_ page: ReaderPageSlot) {
        // 跳页命令尚未消费时，不接受上一位置排队中的页码回报。
        if let scrollRequest, scrollRequest.pageID != page.identity {
            return
        }
        guard openedChapters[page.identity.chapter]?.slots.indices.contains(page.index) == true else {
            return
        }

        if currentPage != page {
            currentPage = page
        }
    }

    /// 只清除 Canvas 已执行的最新定位命令。
    func finishScrollRequest(_ requestID: Int) {
        guard scrollRequest?.id == requestID else {
            return
        }

        scrollRequest = nil
    }

    /// 提交当前章节中的页码跳转；跳到末页时同时预取下一章。
    func jumpToPage(_ pageNumber: Int) {
        guard let currentPage,
              let chapter = chapterContent(
                  for: currentPage.identity.chapter,
              ),
              chapter.totalPageCount > 0
        else {
            return
        }

        let targetIndex = min(max(pageNumber, 1), chapter.totalPageCount) - 1
        guard let targetPage = openedChapters[chapter.identity]?.slots[targetIndex] else { return }

        // 只改变定位；章节窗口和旧位置已开始的请求继续保留。
        discardPendingChapterSwitch()
        scrollRequestSerial += 1
        scrollRequest = ReaderCanvasScrollRequest(
            id: scrollRequestSerial,
            pageID: targetPage.identity,
        )
        self.currentPage = targetPage

        if targetIndex == chapter.totalPageCount - 1 {
            loadNextChapterIfNeeded()
        }
    }

    /// 为当前内容代次生成不可变章节句柄快照。
    var pageAccess: ReaderPageAccess {
        if let downloadedContent {
            return .downloadedAsset(
                sessionMemoryNamespace: downloadedContent.sessionMemoryNamespace,
                payload: downloadedContent.payload,
            )
        }

        let openedChapters = openedChapters
        return .online(
            resolve: { position in
                guard let chapter = openedChapters[position.chapter] else {
                    throw ComicSourceError.invalidIdentity
                }

                return try await chapter.source.pages(containing: position.index)
            },
            loadPage: { [loadOnlinePage] page, consume in
                guard let openedChapter = openedChapters[page.identity.chapter] else {
                    throw ComicSourceError.invalidIdentity
                }

                try await loadOnlinePage(
                    page,
                    openedChapter.source,
                    consume,
                )
            },
        )
    }
}

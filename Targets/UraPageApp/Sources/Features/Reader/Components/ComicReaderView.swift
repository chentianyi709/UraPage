import Foundation
import SwiftUI

/// 三来源共用的阅读页面，组合章节状态、Canvas 和 Reader 控件。
/// 单章只展示页码，多章额外提供切章菜单与相邻章节连续加载。
struct ComicReaderView: View {
    private let chapterMenuOptions: [ReaderChapterMenuOption]
    private let isMultiChapter: Bool

    @State private var viewModel: ComicReaderViewModel

    /// 使用已校验输入和来源组合层提供的章节打开操作创建 Reader。
    init(
        input: ComicReaderInput,
        openChapter: @escaping @Sendable (ChapterIdentity) async throws -> any SourceOpenedChapter,
        loadOnlinePage: @escaping ReaderPageAccess.OnlineChapterPageLoader,
        downloadedContent: ReaderDownloadedContent? = nil,
    ) {
        let chapterMenuOptions = input.chapters.enumerated().map { index, chapter in
            let title = chapter.title.trimmingCharacters(
                in: .whitespacesAndNewlines,
            )
            return ReaderChapterMenuOption(
                id: chapter.identity,
                title: title.isEmpty
                    ? Self.chapterSequenceText(at: index, count: input.chapters.count)
                    : title,
            )
        }
        self.chapterMenuOptions = chapterMenuOptions
        isMultiChapter = input.chapters.count > 1
        _viewModel = State(
            initialValue: ComicReaderViewModel(
                input: input,
                openChapter: openChapter,
                loadOnlinePage: loadOnlinePage,
                downloadedContent: downloadedContent,
            ),
        )
    }

    var body: some View {
        ReaderSessionHost(
            comicSnapshot: viewModel.input.comicSnapshot,
            contentMode: viewModel.input.contentMode,
            currentPosition: currentPosition,
            cancelContentWork: viewModel.cancelContentWork,
            closeContentResources: viewModel.closeContentResources,
        ) { session in
            readerContent(session: session)
        }
    }

    /// 使用当前 ReaderSession 组合 Canvas 和全部阅读控件。
    private func readerContent(session: ReaderSession) -> some View {
        ReaderChromeContainer(
            title: viewModel.input.comicTitle,
            isContentReady: isContentReady,
        ) { chrome in
            let pages = viewModel.pages

            ZStack {
                Color.readerBackground
                    .ignoresSafeArea()

                InitialLoadView(
                    model: viewModel,
                    initialState: { $0.loadState },
                    isEmpty: { $0.pages.isEmpty },
                    loading: {
                        ReaderChapterLoadingView(
                            startPageNumber: (viewModel.input.startPosition?.pageIndex ?? 0) + 1,
                        )
                    },
                    empty: { EmptyStateView(
                        title: "当前章节没有图片",
                        message: isMultiChapter ? "请返回后选择其它章节" : "请返回上一页后重试",
                    ) },
                    failure: { _, error in
                        LoadErrorView(
                            title: "章节加载失败",
                            message: error.message,
                            onRetry: viewModel.retry,
                        )
                    },
                    content: { _ in
                        ReaderCanvasView(
                            snapshot: ReaderCanvasSnapshot(
                                pages: pages,
                                scrollRequest: viewModel.scrollRequest,
                                contentVersion: viewModel.contentVersion,
                                replacementVersion: viewModel.replacementVersion,
                                topBoundaryPresentation: previousChapterBoundaryPresentation,
                                bottomBoundaryPresentation: nextChapterBoundaryPresentation,
                            ),
                            pageAccess: viewModel.pageAccess,
                            chromeTapCount: chrome.tapCount,
                            events: ReaderCanvasEvents(
                                onReachTop: viewModel.loadPreviousChapterIfNeeded,
                                onReachBottom: viewModel.loadNextChapterIfNeeded,
                                onRetryTopBoundary: viewModel.retryPreviousChapter,
                                onRetryBottomBoundary: viewModel.retryNextChapter,
                                onCurrentPageChange: viewModel.updateCurrentPage,
                                onStablePageChange: { page in
                                    if let position = position(for: page) {
                                        session.recordStablePosition(position)
                                    }
                                },
                                onScrollRequestHandled: viewModel.finishScrollRequest,
                                onTap: chrome.onToggle,
                                onScrollStart: chrome.onScrollStart,
                            ),
                            session: session,
                        )
                    },
                )

                if viewModel.chapterSwitchState.loadingChapterIdentity != nil {
                    ReaderChapterLoadingView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.readerBackground)
                        .contentShape(Rectangle())
                        .allowsHitTesting(true)
                }

                ReaderPageIndicatorPanel(
                    presentation: pageIndicatorPresentation,
                    chapters: chapterMenuOptions,
                    onSelectChapter: viewModel.selectChapter,
                )
                .padding(.leading, 16)
                .padding(.bottom, 18)
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity,
                    alignment: .bottomLeading,
                )

                ReaderPageControlsPanel(
                    isVisible: chrome.isVisible,
                    currentPage: currentPage,
                    pageTotal: currentPageTotal,
                    onCommit: viewModel.jumpToPage,
                )

                #if DEBUG
                    ReaderFPSMonitorView()
                #endif
            }
        }
        .task {
            viewModel.loadIfNeeded()
        }
        .onChange(of: viewModel.chapterSwitchState) { _, state in
            handleChapterSwitchStateChange(state)
        }
    }

    /// Canvas 已有可阅读内容，且未被切章加载页面遮挡。
    private var isContentReady: Bool {
        viewModel.loadState == .loaded
            && !viewModel.pages.isEmpty
            && viewModel.chapterSwitchState.loadingChapterIdentity == nil
    }

    private func currentPosition() -> ReaderSessionPosition? {
        viewModel.currentPage?.resolvedPage.flatMap(position(for:))
    }

    private func position(for page: ComicPage) -> ReaderSessionPosition? {
        guard let chapterIndex = viewModel.chapterIndexByID[page.identity.chapter] else {
            return nil
        }

        // 章节标题来自入口列表；图片分页响应不一定包含标题。
        return ReaderSessionPosition(
            pageIdentity: page.identity,
            pageIndex: page.index,
            chapterTitle: viewModel.input.chapters[chapterIndex].title,
        )
    }

    /// 把上一章状态转换为 Canvas 顶部占位内容。
    private var previousChapterBoundaryPresentation: ReaderCanvasChapterBoundaryPresentation? {
        guard let earliestChapterIndex = viewModel.earliestChapterIndex,
              earliestChapterIndex > viewModel.input.chapters.startIndex
        else {
            return nil
        }

        let previousIndex = viewModel.input.chapters.index(
            before: earliestChapterIndex,
        )
        return chapterBoundaryPresentation(
            state: viewModel.previousChapterLoadState,
            chapterIndex: previousIndex,
        )
    }

    /// 把下一章状态转换为 Canvas 底部占位内容。
    private var nextChapterBoundaryPresentation: ReaderCanvasChapterBoundaryPresentation? {
        guard let latestChapterIndex = viewModel.latestChapterIndex,
              latestChapterIndex < viewModel.input.chapters.index(
                  before: viewModel.input.chapters.endIndex,
              )
        else {
            return nil
        }

        let nextIndex = viewModel.input.chapters.index(after: latestChapterIndex)
        return chapterBoundaryPresentation(
            state: viewModel.nextChapterLoadState,
            chapterIndex: nextIndex,
        )
    }

    /// 组装相邻章加载和失败重试文案。
    private func chapterBoundaryPresentation(
        state: ReaderAdjacentChapterLoadState,
        chapterIndex: Int,
    ) -> ReaderCanvasChapterBoundaryPresentation? {
        let chapterText = Self.chapterSequenceText(
            at: chapterIndex,
            count: viewModel.input.chapters.count,
        )
        switch state {
        case .idle:
            return nil
        case .loading:
            return .loading("正在加载\(chapterText)")
        case .failed:
            return .failed("\(chapterText)加载失败，点击重试")
        }
    }

    /// 组装菜单切章前后的页码展示数据。
    private func pageIndicatorPresentation() -> ReaderPageIndicatorPresentation? {
        let state: ReaderPageIndicatorState
        let chapterIdentity: ChapterIdentity

        if let loadingChapterIdentity =
            viewModel.chapterSwitchState.loadingChapterIdentity {
            state = .switchingChapter
            chapterIdentity = loadingChapterIdentity
        } else {
            guard let page = viewModel.currentPage,
                  let chapter = viewModel.chapterContent(
                      for: page.identity.chapter,
                  )
            else {
                return nil
            }

            state = .loaded(
                pageNumber: page.index + 1,
                pageTotal: chapter.totalPageCount,
            )
            chapterIdentity = chapter.identity
        }

        guard let chapterIndex = viewModel.chapterIndexByID[chapterIdentity],
              chapterMenuOptions.indices.contains(chapterIndex)
        else {
            return nil
        }

        return ReaderPageIndicatorPresentation(
            state: state,
            chapterTitle: isMultiChapter
                ? chapterMenuOptions[chapterIndex].title
                : nil,
            selectedChapterID: chapterIdentity,
        )
    }

    /// 菜单切章期间不向页码控件提供当前页。
    private func currentPage() -> ReaderPageSlot? {
        guard viewModel.chapterSwitchState.loadingChapterIdentity == nil else {
            return nil
        }

        return viewModel.currentPage
    }

    /// 使用 O(1) 已打开章节映射返回当前总页数。
    private func currentPageTotal() -> Int? {
        guard let currentPage = viewModel.currentPage else {
            return nil
        }

        return viewModel.chapterContent(
            for: currentPage.identity.chapter,
        )?.totalPageCount
    }

    /// 显示一次切章失败并立即消费状态。
    private func handleChapterSwitchStateChange(
        _ state: ReaderChapterSwitchState,
    ) {
        guard state == .failed else {
            return
        }

        ToastCenter.shared.show("章节切换失败，请稍后重试", type: .error)
        viewModel.consumeChapterSwitchFailure()
    }

    /// 在来源没有可显示标题时，按最旧到最新的顺序生成章节兜底文案。
    private static func chapterSequenceText(at index: Int, count: Int) -> String {
        count > 1 ? "第 \(index + 1) 章节" : "仅1章节"
    }
}

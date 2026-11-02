import SwiftUI

/// 为一个 Reader destination 创建并关闭独立 ReaderSession。
struct ReaderSessionHost<Content: View>: View {
    @Environment(\.readerImageCache) private var readerImageCache
    @Environment(\.readerSessionScope) private var sessionScope
    @Environment(\.readerProgressRecorder) private var progressRecorder
    @Environment(\.scenePhase) private var scenePhase

    private let comicSnapshot: LibraryComicSnapshot
    private let contentMode: ComicContentMode
    private let currentPosition: () -> ReaderSessionPosition?
    private let cancelContentWork: () -> [Task<Void, Never>]
    private let closeContentResources: () async throws -> Void
    private let content: (ReaderSession) -> Content

    @State private var session: ReaderSession?

    init(
        comicSnapshot: LibraryComicSnapshot,
        contentMode: ComicContentMode,
        currentPosition: @escaping () -> ReaderSessionPosition?,
        cancelContentWork: @escaping () -> [Task<Void, Never>],
        closeContentResources: @escaping () async throws -> Void,
        @ContentBuilder content: @escaping (ReaderSession) -> Content,
    ) {
        self.comicSnapshot = comicSnapshot
        self.contentMode = contentMode
        self.currentPosition = currentPosition
        self.cancelContentWork = cancelContentWork
        self.closeContentResources = closeContentResources
        self.content = content
    }

    var body: some View {
        Group {
            if let session {
                content(session)
            } else {
                Color.readerBackground.ignoresSafeArea()
            }
        }
        .onAppear(perform: createSessionIfNeeded)
        .onDisappear {
            guard let session else { return }

            // 返回详情可能先于异步 close 完成；先排队最终位置供详情查询等待。
            session.flushProgress()

            Task {
                await sessionScope.close(session)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                session?.flushProgress()
            }
        }
    }

    private func createSessionIfNeeded() {
        guard session == nil else { return }
        guard !sessionScope.isClosed else { return }

        let session = ReaderSession(
            comicSnapshot: comicSnapshot,
            contentMode: contentMode,
            progressRecorder: progressRecorder,
            imageCache: readerImageCache,
            currentPosition: currentPosition,
            cancelContentWork: cancelContentWork,
            closeContentResources: closeContentResources,
        )
        sessionScope.register(session)
        self.session = session
    }
}

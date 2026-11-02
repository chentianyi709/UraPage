import Foundation

/// Reader 最终进度采样所需的完整页面位置。
struct ReaderSessionPosition {
    let pageIdentity: PageIdentity
    let pageIndex: Int
    let chapterTitle: String
}

/// 独占一次 Reader destination 的页面任务与图片缓存 lease。
@MainActor
final class ReaderSession {
    let id = UUID()
    let pageImageLoader: ReaderPageImageLoader

    private let progressRecorder: ReaderProgressRecorder
    private var currentPosition: () -> ReaderSessionPosition?
    private var cancelContentWork: () -> [Task<Void, Never>]
    private var closeContentResources: () async throws -> Void
    private weak var canvas: ReaderCanvasUIView?
    private var lastStablePosition: ReaderSessionPosition?
    private var detachedPageTasks: [Task<Void, Never>] = []
    private var closeTask: Task<Void, any Error>?

    init(
        comicSnapshot: LibraryComicSnapshot,
        contentMode: ComicContentMode,
        progressRecorder: ReaderProgressRecorder,
        imageCache: ReaderImageCacheStore,
        currentPosition: @escaping () -> ReaderSessionPosition?,
        cancelContentWork: @escaping () -> [Task<Void, Never>],
        closeContentResources: @escaping () async throws -> Void,
    ) {
        self.progressRecorder = progressRecorder
        self.currentPosition = currentPosition
        self.cancelContentWork = cancelContentWork
        self.closeContentResources = closeContentResources
        pageImageLoader = ReaderPageImageLoader(
            cacheLease: imageCache.makeLease(sessionID: id),
        )
        progressRecorder.beginSession(id, comic: comicSnapshot, contentMode: contentMode)
    }

    func recordStablePosition(_ position: ReaderSessionPosition) {
        lastStablePosition = position
        progressRecorder.recordStablePosition(
            sessionID: id,
            pageIdentity: position.pageIdentity,
            pageIndex: position.pageIndex,
            chapterTitle: position.chapterTitle,
        )
    }

    func flushProgress() {
        captureCurrentPosition()
        progressRecorder.flushSession(id)
    }

    func attachCanvas(_ canvas: ReaderCanvasUIView) {
        guard closeTask == nil else {
            canvas.stopAndCancelAllWork()
            return
        }

        self.canvas = canvas
    }

    func detachCanvas(_ canvas: ReaderCanvasUIView) {
        // dismantle 可能先于 onDisappear；在节点被清空前采样真实视口。
        capturePosition(from: canvas)
        detachedPageTasks.append(contentsOf: canvas.stopAndCancelAllWork())
        if self.canvas === canvas {
            self.canvas = nil
        }
    }

    /// 先停止内容与 Canvas 工作，再释放来源句柄，最后释放图片 lease。
    func close() async throws {
        if let closeTask {
            try await closeTask.value
            return
        }

        captureCurrentPosition()
        let progressRecorder = progressRecorder
        let sessionID = id

        var tasks = detachedPageTasks
        detachedPageTasks.removeAll()
        if let canvas {
            tasks.append(contentsOf: canvas.stopAndCancelAllWork())
            self.canvas = nil
        }
        tasks.append(contentsOf: cancelContentWork())
        let closeContentResources = closeContentResources
        currentPosition = { nil }
        cancelContentWork = { [] }

        let task = Task {
            await progressRecorder.endSession(sessionID)
            for contentTask in tasks {
                await contentTask.value
            }
            self.closeContentResources = {}
            var cleanupError: (any Error)?
            do {
                try await closeContentResources()
            } catch {
                cleanupError = error
            }
            await pageImageLoader.close()
            if let cleanupError {
                throw cleanupError
            }
        }
        closeTask = task
        do {
            try await task.value
        } catch {
            closeTask = nil
            throw error
        }
    }

    private func captureCurrentPosition() {
        if let canvas, capturePosition(from: canvas) {
            return
        }
        if let position = lastStablePosition ?? currentPosition() {
            recordStablePosition(position)
        }
    }

    /// 页码展示有节流；退出和后台保存直接读取 Canvas，避免落后于用户实际位置。
    @discardableResult
    private func capturePosition(from canvas: ReaderCanvasUIView) -> Bool {
        guard let node = canvas.mostRelevantVisibleNode(),
              let page = node.page.resolvedPage else { return false }

        canvas.onStablePageChange?(page)
        return true
    }
}

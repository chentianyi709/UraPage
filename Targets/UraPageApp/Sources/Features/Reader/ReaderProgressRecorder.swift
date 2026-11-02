import Foundation
import SwiftUI

extension EnvironmentValues {
    /// 阅读进度写入器存储槽；写入用 `\.readerProgressRecorderStorage`（写入路径先读缺省，缺省必须可读）。
    @Entry var readerProgressRecorderStorage: ReaderProgressRecorder?

    /// 读取入口：由 App 入口安装，未安装即暴露装配错误。
    var readerProgressRecorder: ReaderProgressRecorder {
        guard let readerProgressRecorderStorage else {
            preconditionFailure("ReaderProgressRecorder 未由 App 入口安装")
        }

        return readerProgressRecorderStorage
    }
}

/// 一个进程共享的进度写入边界：稳定页防抖，同一作品与内容模式串行保存，退出可等待最终写入。
@MainActor
final class ReaderProgressRecorder {
    private struct Session {
        let comic: LibraryComicSnapshot
        let identity: ReadingProgressIdentity
        var latest: ReadingProgressUpdate?
        var generation = 0
        var debounceTask: Task<Void, Never>?
    }

    private struct Write {
        let id: UUID
        let update: ReadingProgressUpdate
        let task: Task<Void, Never>
        var didFail = false
    }

    private let store: ReadingHistoryStore
    private var sessions: [UUID: Session] = [:]
    private var activeSessionByIdentity: [ReadingProgressIdentity: UUID] = [:]
    private var writes: [ReadingProgressIdentity: Write] = [:]

    init(store: ReadingHistoryStore) {
        self.store = store
    }

    /// 详情页读取阅读进度；取消原样抛出，其它读取失败也交给页面边界处理。
    ///
    /// 不在这里把失败折叠成 `nil`：页面需要区分“没有进度”和“本地记录读取失败”，
    /// 前者展示普通开始阅读，后者至少留下错误日志而不是伪造位置。
    func detailProgress(
        for identity: ComicIdentity,
        contentMode: ComicContentMode,
    ) async throws -> ReadingProgress? {
        let progress = try await progress(for: ReadingProgressIdentity(
            comic: identity,
            contentMode: contentMode,
        ))
        try Task.checkCancellation()
        return progress
    }

    /// 详情页返回时先等待当前作品与内容模式排队中的写入，再读取已保存的位置。
    func progress(for identity: ReadingProgressIdentity) async throws -> ReadingProgress? {
        if let write = writes[identity] {
            await write.task.value
        }
        return try await store.progress(for: identity)
    }

    func beginSession(_ id: UUID, comic: LibraryComicSnapshot, contentMode: ComicContentMode) {
        guard sessions[id] == nil else { return }

        let identity = ReadingProgressIdentity(comic: comic.identity, contentMode: contentMode)
        if let previousID = activeSessionByIdentity[identity] {
            // 先排队旧位置，保留旧 session 到它自己的 close 等待完成。
            flushSession(previousID)
        }
        sessions[id] = Session(comic: comic, identity: identity)
        activeSessionByIdentity[identity] = id
    }

    /// 只接受当前会话的有效 Canvas 稳定位置。
    func recordStablePosition(
        sessionID: UUID,
        pageIdentity: PageIdentity,
        pageIndex: Int,
        chapterTitle: String,
    ) {
        guard var session = sessions[sessionID],
              activeSessionByIdentity[session.identity] == sessionID,
              pageIdentity.chapter.comic == session.comic.identity,
              !pageIdentity.pageID.isEmpty,
              pageIndex >= 0
        else { return }

        session.debounceTask?.cancel()
        session.generation &+= 1
        let generation = session.generation
        session.latest = ReadingProgressUpdate(
            comic: session.comic,
            contentMode: session.identity.contentMode,
            pageIdentity: pageIdentity,
            pageIndex: pageIndex,
            chapterTitle: chapterTitle,
        )
        session.debounceTask = Task { @concurrent [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(500))
            } catch {
                return
            }
            await self?.saveLatest(sessionID: sessionID, generation: generation)
        }
        sessions[sessionID] = session
    }

    /// 后台切换时立即排队保存；关闭时还会等待写入完成。
    func flushSession(_ id: UUID) {
        guard var session = sessions[id],
              activeSessionByIdentity[session.identity] == id
        else { return }

        session.debounceTask?.cancel()
        session.generation &+= 1
        session.debounceTask = nil
        sessions[id] = session
        if let update = session.latest {
            enqueue(update)
        }
    }

    /// 拒绝旧会话迟到事件，并等待该漫画先前及最终位置依次写完。
    func endSession(_ id: UUID) async {
        guard let session = sessions[id] else { return }

        let identity = session.identity

        finish(id)
        if let write = writes[identity] {
            await write.task.value
            if writes[identity]?.id == write.id {
                writes.removeValue(forKey: identity)
            }
        }
    }

    private func finish(_ id: UUID) {
        guard let session = sessions.removeValue(forKey: id) else { return }

        session.debounceTask?.cancel()
        let identity = session.identity
        if activeSessionByIdentity[identity] == id {
            activeSessionByIdentity.removeValue(forKey: identity)
            if let update = session.latest {
                enqueue(update)
            }
        }
    }

    private func saveLatest(sessionID: UUID, generation: Int) {
        guard var session = sessions[sessionID],
              session.generation == generation,
              activeSessionByIdentity[session.identity] == sessionID
        else { return }

        session.debounceTask = nil
        sessions[sessionID] = session
        if let update = session.latest {
            enqueue(update)
        }
    }

    /// 后排请求等待前排结果；旧会话不可能在新会话位置之后落库。
    private func enqueue(_ update: ReadingProgressUpdate) {
        let identity = update.identity
        // 稳定页、后台和退出可能连续提交同一位置；失败记录仍允许下次提交重试。
        if let write = writes[identity], write.update == update, !write.didFail {
            return
        }
        let previous = writes[identity]?.task
        let store = store
        let writeID = UUID()
        let task = Task { @concurrent [weak self] in
            await previous?.value
            do {
                try await store.record(update)
            } catch {
                AppLogger.error(
                    "阅读进度保存失败，errorType=\(String(reflecting: type(of: error)))",
                    category: "Reader.Progress",
                )
                await MainActor.run {
                    if self?.writes[identity]?.id == writeID {
                        self?.writes[identity]?.didFail = true
                    }
                    ToastCenter.shared.show("阅读进度保存失败，本次位置可能未保存", type: .error)
                }
            }
        }
        writes[identity] = Write(id: writeID, update: update, task: task)
    }
}

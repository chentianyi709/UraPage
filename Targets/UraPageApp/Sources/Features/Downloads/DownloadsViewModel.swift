import Observation
import SwiftUI

enum DownloadsDisplayError: Equatable, Sendable {
    case loadFailed

    var message: String {
        "无法读取本地下载记录，请稍后重试"
    }
}

/// 管理「下载记录」首屏、分页、下载变更订阅与暂停／继续／重试动作。
///
/// 分页按「未完成组在前、已完成组在后」读取：未完成组按最近一次入队时间倒序，已完成组按完成时间倒序；
/// 结构变化时按**已加载窗口**重读，保持列表长度与滚动位置，同时保证丢弃中间结构事件也不会漏状态。
@Observable
@MainActor
final class DownloadsViewModel {
    private(set) var items: [DownloadedComicSummary] = []
    private(set) var loadState: InitialLoadState<DownloadsDisplayError> = .idle
    private(set) var isLoadingMore = false
    private(set) var loadMoreError: String?

    var canLoadMore: Bool {
        nextCursor != nil
    }

    @ObservationIgnored private let manager: DownloadManager
    @ObservationIgnored private var nextCursor: DownloadedComicCursor?
    @ObservationIgnored private var streamTask: Task<Void, Never>?
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var moreTask: Task<Void, Never>?
    @ObservationIgnored private var generation = 0
    /// 已应用的结构版本；版本变化时重读已加载窗口，逐页进度只原地替换。
    @ObservationIgnored private var appliedRevision: UInt64 = 0
    /// 是否已接收过第一条事件；首条对齐版本后重读一次，覆盖订阅建立与首读之间的结构变化。
    @ObservationIgnored private var hasAppliedRevision = false

    init(manager: DownloadManager) {
        self.manager = manager
    }

    deinit {
        streamTask?.cancel()
        loadTask?.cancel()
        moreTask?.cancel()
    }

    /// 订阅下载变更流；重复调用保持单条订阅。
    func start() {
        guard streamTask == nil else { return }

        let manager = manager
        streamTask = Task { [weak self] in
            let stream = await manager.makeChangeStream()
            for await change in stream {
                guard let self else { return }

                handle(change)
            }
        }
    }

    /// 重读已加载窗口（首屏即第一页）；结构变化与手动重试都走这里。
    func refresh() {
        loadTask?.cancel()
        moreTask?.cancel()
        moreTask = nil
        isLoadingMore = false
        loadMoreError = nil
        generation &+= 1
        let generation = generation
        let manager = manager
        // 至少一页；已加载更多时按已加载数量补齐，避免结构变化把列表截短。
        let target = max(items.count, DownloadManager.summariesPageSize)
        if items.isEmpty {
            loadState = .loading
        }

        loadTask = Task { [weak self] in
            do {
                // 一次读取已加载窗口；结构变化不再按 30 条一页循环查询。
                let page = try await manager.summariesPage(after: nil, limit: target)
                guard let self, generation == self.generation else { return }

                items = page.items
                nextCursor = page.nextCursor
                loadState = .loaded
                loadMoreError = nil
                loadTask = nil
            } catch is CancellationError {
                return
            } catch {
                guard let self, generation == self.generation else { return }

                AppLogger.error(
                    "下载记录读取失败，errorType=\(String(reflecting: type(of: error)))",
                    category: "App.Download",
                )
                if items.isEmpty {
                    loadState = .failed(.loadFailed)
                } else {
                    loadMoreError = "刷新失败，点击重试"
                }
                loadTask = nil
            }
        }
    }

    /// 触底续载下一页。
    func loadMoreIfNeeded() {
        guard loadTask == nil, moreTask == nil,
              loadMoreError == nil, let cursor = nextCursor
        else { return }

        let generation = generation
        let manager = manager
        isLoadingMore = true
        moreTask = Task { [weak self] in
            do {
                let page = try await manager.summariesPage(after: cursor)
                try Task.checkCancellation()
                guard let self, generation == self.generation else { return }

                items.append(contentsOf: page.items)
                nextCursor = page.nextCursor
                isLoadingMore = false
                moreTask = nil
            } catch is CancellationError {
                return
            } catch {
                guard let self, generation == self.generation else { return }

                AppLogger.error(
                    "下载记录分页失败，errorType=\(String(reflecting: type(of: error)))",
                    category: "App.Download",
                )
                isLoadingMore = false
                loadMoreError = "加载更多失败，点击重试"
                moreTask = nil
            }
        }
    }

    func retryLoadMore() {
        guard loadTask == nil else { return }

        if nextCursor == nil {
            refresh()
        } else {
            loadMoreError = nil
            loadMoreIfNeeded()
        }
    }

    /// 按下载状态暂停、继续或重试；已完成的作品不在此处理，由页面路由到离线详情。
    func toggle(_ identity: ComicIdentity) {
        guard let item = items.first(where: { $0.identity == identity }) else { return }

        switch item.state {
        case .queued, .downloading:
            Task { await manager.pause(identity) }
        case .paused:
            Task { await manager.resume(identity) }
        case .failed:
            Task { await manager.retry(identity) }
        case .completed:
            break
        }
    }

    /// 删除一个作品的下载：先从已加载窗口带动画移除（后面的卡片前移补位），
    /// 再停止在途任务、删除资产与记录；失败时重读窗口把这一项恢复回来。
    ///
    /// 不能等 `manager.remove` 返回再移除：它结束前会发布结构变化事件，视图模型收到事件
    /// 会重读窗口，这一项可能在动画之前就被无动画地读走，删除动画时有时无。
    func delete(_ identity: ComicIdentity) async throws {
        withAnimation(.snappy) {
            items.removeAll { $0.identity == identity }
        }

        do {
            try await manager.remove(identity)
        } catch {
            // 删除未生效：以库里的真实状态为准重读（失败时 manager 不发结构事件）。
            refresh()
            throw error
        }
    }

    /// 结构版本变化时重读已加载窗口；逐页进度原地替换，不重排。
    ///
    /// 事件按结构版本连续下发：版本相同是逐页进度，版本 +1 且带快照就是这一条结构变化本身，
    /// 两种情况都可以原地替换；只有版本跳跃（中间事件被 `bufferingNewest(1)` 丢弃）或结构变化
    /// 不带快照（入队／继续／重试）时才按已加载窗口重读，保证丢弃事件也不漏状态。
    private func handle(_ change: DownloadChange) {
        guard hasAppliedRevision else {
            hasAppliedRevision = true
            appliedRevision = change.revision
            refresh()
            return
        }

        let hasGap = change.revision > appliedRevision &+ 1
        appliedRevision = change.revision

        guard !hasGap else {
            refresh()
            return
        }

        if let summary = change.progress {
            replace(summary)
        } else {
            refresh()
        }
    }

    private func replace(_ summary: DownloadedComicSummary) {
        guard let index = items.firstIndex(where: { $0.identity == summary.identity }) else { return }

        // 完成事件携带进度快照，但滚动列表的排序仍以持久化分组为准；跨组时重读已加载窗口，
        // 让作品立即从「未完成」移到「已完成」首位，而不是原地替换后留在旧位置。
        let wasCompleted = items[index].state == .completed
        let isCompleted = summary.state == .completed
        guard wasCompleted == isCompleted else {
            refresh()
            return
        }

        items[index] = summary
    }
}

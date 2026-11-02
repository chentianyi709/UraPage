import Observation
import SwiftUI

/// 历史网格的卡片值：漫画展示项 + 完整进度身份（在线／离线各自独立）。
struct ReadingHistoryCard: Identifiable {
    let comic: ComicListItem
    let progressIdentity: ReadingProgressIdentity

    var id: ReadingProgressIdentity {
        progressIdentity
    }
}

enum ReadingHistoryDisplayError: Equatable, Sendable {
    case loadFailed

    var message: String {
        "无法读取本地阅读记录，请稍后重试"
    }
}

/// 管理阅读记录首屏、分页和切回书架后的刷新。
@Observable
@MainActor
final class ReadingHistoryViewModel {
    private(set) var items: [ReadingHistoryCard] = []
    private(set) var loadState: InitialLoadState<ReadingHistoryDisplayError> = .idle
    private(set) var isLoadingMore = false
    private(set) var loadMoreError: String?

    var canLoadMore: Bool {
        nextCursor != nil
    }

    @ObservationIgnored private let store: ReadingHistoryStore
    @ObservationIgnored private let sourceNames: [ComicSourceID: String]
    @ObservationIgnored private var nextCursor: ReadingHistoryCursor?
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var moreTask: Task<Void, Never>?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var needsRefresh = false

    init(store: ReadingHistoryStore, sourceNames: [ComicSourceID: String]) {
        self.store = store
        self.sourceNames = sourceNames
    }

    deinit {
        loadTask?.cancel()
        moreTask?.cancel()
    }

    func refresh() {
        loadTask?.cancel()
        moreTask?.cancel()
        moreTask = nil
        generation &+= 1
        let generation = generation
        let store = store
        // 已经成功加载过（包括结果为空）的刷新保持当前展示静默进行：
        // 把空态重画成骨架屏会让每次切回历史页都闪一下；首次加载与失败重试仍进入加载中。
        if items.isEmpty, loadState != .loaded {
            loadState = .loading
        }
        isLoadingMore = false
        loadMoreError = nil

        loadTask = Task { [weak self] in
            do {
                // 进入／刷新历史页时按保留档位清理一次过期记录；分页加载不再清理，避免打断分页。
                try? await store.pruneExpiredIfNeeded()
                let page = try await store.page(after: nil)
                try Task.checkCancellation()
                guard let self, self.generation == generation else { return }

                items = page.items.map(makeCard)
                nextCursor = page.nextCursor
                needsRefresh = false
                loadState = .loaded
                loadTask = nil
            } catch is CancellationError {
                return
            } catch {
                guard let self, self.generation == generation else { return }

                AppLogger.error("阅读记录刷新失败，errorType=\(type(of: error))", category: "Library.History")

                if items.isEmpty {
                    loadState = .failed(.loadFailed)
                } else {
                    needsRefresh = true
                    loadMoreError = "刷新失败，点击重试"
                }
                loadTask = nil
            }
        }
    }

    func loadMoreIfNeeded() {
        guard loadTask == nil, moreTask == nil, !needsRefresh,
              loadMoreError == nil, let cursor = nextCursor
        else { return }

        let generation = generation
        let store = store
        isLoadingMore = true
        moreTask = Task { [weak self] in
            do {
                let page = try await store.page(after: cursor)
                try Task.checkCancellation()
                guard let self, self.generation == generation else { return }

                items.append(contentsOf: page.items.map(makeCard))
                nextCursor = page.nextCursor
                isLoadingMore = false
                moreTask = nil
            } catch is CancellationError {
                return
            } catch ReadingHistoryError.historyChanged {
                guard let self, self.generation == generation else { return }

                moreTask = nil
                refresh()
            } catch {
                guard let self, self.generation == generation else { return }

                AppLogger.error("阅读记录分页失败，errorType=\(type(of: error))", category: "Library.History")

                isLoadingMore = false
                loadMoreError = "加载更多失败，点击重试"
                moreTask = nil
            }
        }
    }

    func retryLoadMore() {
        if loadTask != nil {
            return
        }
        if needsRefresh || nextCursor == nil {
            refresh()
        } else {
            loadMoreError = nil
            loadMoreIfNeeded()
        }
    }

    /// 从观看历史删除一个作品的全部阅读记录（在线与离线进度一并删除）。
    ///
    /// 删除成功只从已加载窗口移除该卡片；分页游标不失效（删除不改变其余行的排序位置）。
    /// 同时取消在途刷新／分页并递增代次：历史没有变更流，否则删除前发出的查询可能把
    /// 已删除的卡片重新写回列表。
    func delete(_ card: ReadingHistoryCard) async -> Bool {
        do {
            try await store.delete(comic: card.progressIdentity.comic)
        } catch {
            AppLogger.error("阅读记录删除失败，errorType=\(type(of: error))", category: "Library.History")
            return false
        }

        loadTask?.cancel()
        loadTask = nil
        moreTask?.cancel()
        moreTask = nil
        isLoadingMore = false
        generation &+= 1
        // 分页失败的错误在删除后已无意义；刷新失败保留 banner/retry（needsRefresh 仍会阻止续载）。
        if !needsRefresh {
            loadMoreError = nil
        }
        withAnimation(.snappy) {
            items.removeAll { $0.progressIdentity.comic == card.progressIdentity.comic }
        }
        return true
    }

    /// 每批结果只转换一次，分页状态变化时不在 body 重新映射全部历史记录。
    private func makeCard(_ item: ReadingHistoryItem) -> ReadingHistoryCard {
        ReadingHistoryCard(
            comic: ComicListItem(
                identity: item.comic.identity,
                title: item.comic.title,
                subtitle: [
                    item.comic.authors.joined(separator: "、"),
                    sourceNames[item.comic.identity.sourceID] ?? "",
                ]
                .filter { !$0.isEmpty }
                .joined(separator: " · "),
                cover: item.comic.cover,
            ),
            progressIdentity: item.id,
        )
    }
}

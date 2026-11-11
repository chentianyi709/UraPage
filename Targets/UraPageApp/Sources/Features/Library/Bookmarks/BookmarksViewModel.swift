import Observation
import SwiftUI

/// 书签页可展示的加载错误。
enum BookmarksDisplayError: Equatable, Sendable {
    case loadFailed

    var message: String {
        "无法读取本地书签收藏，请稍后重试"
    }
}

/// 书架「书签」页的一组内容：同一来源的收藏（作者／分类／标签混排），组内保持最近收藏在前。
struct BookmarksSection: Identifiable {
    let sourceID: ComicSourceID
    let entries: [Bookmark]

    var id: String {
        sourceID.rawValue
    }
}

/// 书架「书签」页的状态：一次读取全部收藏并按来源分组，删除时本地先动、失败再重读。
///
/// 不分页：书签量级有限，一次 `fetch` 之后交给 `LazyVStack` 只构建可见的胶囊，
/// 首屏与滚动都不需要额外的窗口管理；分页要处理游标失效、跨页写入与续载失败，收益不抵复杂度。
@Observable
@MainActor
final class BookmarksViewModel {
    private(set) var sections: [BookmarksSection] = []
    private(set) var loadState: InitialLoadState<BookmarksDisplayError> = .idle

    @ObservationIgnored private let store: BookmarkStore

    @ObservationIgnored private var loadTask: Task<Void, Never>?

    /// 写操作串行队列：上一次落盘失败触发的重读不会插到下一次写入之前。
    ///
    /// operation 里只能同步地发起 `refresh()`（它自己创建任务）；不要在 operation 内 `await` 刷新结果——
    /// 刷新会先 `await mutationTail`，也就是当前这个写任务本身，会形成环。
    @ObservationIgnored private var mutationTail: Task<Void, Never>?

    @ObservationIgnored private var generation = 0

    init(store: BookmarkStore) {
        self.store = store
    }

    deinit {
        loadTask?.cancel()
    }

    /// 读取全部收藏；已加载过（包括空结果）的刷新保持当前展示，避免切回该分区时闪骨架。
    func refresh() {
        loadTask?.cancel()
        generation &+= 1
        let generation = generation
        let pendingMutation = mutationTail

        if sections.isEmpty, loadState != .loaded {
            loadState = .loading
        }

        loadTask = Task { [weak self] in
            guard let self else { return }

            // 等正在落盘的删除／清空结束，避免刚删掉的条目被这次读取重新带回来。
            await pendingMutation?.value
            guard generation == self.generation else { return }

            do {
                let entries = try await store.entries()
                guard generation == self.generation else { return }

                sections = Self.group(entries)
                loadState = .loaded
            } catch {
                guard generation == self.generation else { return }

                AppLogger.warning(
                    "书签收藏读取失败，errorType=\(type(of: error))",
                    category: "Bookmarks",
                )

                // 已有内容时保留当前展示，不让一次后台刷新失败把整页换成错误页。
                if sections.isEmpty {
                    loadState = .failed(.loadFailed)
                } else {
                    loadState = .loaded
                }
            }
        }
    }

    /// 删除一条收藏：先带动画本地移除（剩余胶囊平滑回流），再落盘；失败提示并重读。
    func remove(_ bookmark: Bookmark) {
        invalidateInFlightLoads()
        withAnimation(.snappy) {
            sections = sections.compactMap { section in
                // 按身份键过滤：payload 不参与身份，重收藏后两者可能不同。
                let entries = section.entries.filter { $0.identityKey != bookmark.identityKey }
                return entries.isEmpty
                    ? nil
                    : BookmarksSection(sourceID: section.sourceID, entries: entries)
            }
        }

        enqueueMutation { [weak self] in
            guard let self else { return }

            do {
                try await store.remove(bookmark)
            } catch {
                AppLogger.warning(
                    "书签收藏删除失败，errorType=\(type(of: error))",
                    category: "Bookmarks",
                )
                ToastCenter.shared.show("删除失败，请稍后重试", type: .error)
                // 本地已经先移除了，落盘失败要靠重读把它恢复回来。
                refresh()
            }
        }
    }

    /// 清空一个来源：先带动画整组移除（下方分组上移补位），再落盘；失败提示并重读。
    func clear(sourceID: ComicSourceID) {
        invalidateInFlightLoads()
        withAnimation(.snappy) {
            sections.removeAll { $0.sourceID == sourceID }
        }

        enqueueMutation { [weak self] in
            guard let self else { return }

            do {
                try await store.removeAll(sourceID: sourceID)
            } catch {
                AppLogger.warning(
                    "书签分组清除失败，source=\(sourceID.rawValue) errorType=\(type(of: error))",
                    category: "Bookmarks",
                )
                ToastCenter.shared.show("清除失败，请稍后重试", type: .error)
                refresh()
            }
        }
    }

    /// 删除会改变列表：让在途刷新结果失效，避免旧结果把已删条目写回。
    private func invalidateInFlightLoads() {
        loadTask?.cancel()
        loadTask = nil
        generation &+= 1
    }

    /// 把写操作串到同一个队列：前一次落盘失败触发的重读不会插到后一次写入之前。
    ///
    /// 完成的任务留在 `mutationTail` 上不清理：后来者 `await` 已完成的任务会立即返回，
    /// 也没有任何地方依赖「队列空闲」这个状态。
    private func enqueueMutation(_ operation: @escaping @MainActor () async -> Void) {
        let previous = mutationTail

        mutationTail = Task { @MainActor in
            await previous?.value
            await operation()
        }
    }

    /// 按来源分组，组序取「最近收藏先出现」的首次出现顺序；实际展示顺序由页面按来源 Tab 顺序排。
    private static func group(_ entries: [Bookmark]) -> [BookmarksSection] {
        var order: [ComicSourceID] = []
        var grouped: [ComicSourceID: [Bookmark]] = [:]

        for entry in entries {
            if grouped[entry.sourceID] == nil {
                order.append(entry.sourceID)
            }

            grouped[entry.sourceID, default: []].append(entry)
        }

        return order.compactMap { sourceID in
            grouped[sourceID].map { BookmarksSection(sourceID: sourceID, entries: $0) }
        }
    }
}

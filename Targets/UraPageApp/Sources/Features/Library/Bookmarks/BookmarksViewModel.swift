import Observation
import SwiftUI

/// 书签页可展示的加载错误。
enum BookmarksDisplayError: Equatable, Sendable {
    case loadFailed

    var message: String {
        "无法读取本地书签收藏，请稍后重试"
    }
}

/// 书架「书签」页的一段：一个维度（分类／标签／未登记维度）下的全部收藏，跨来源。
struct BookmarkGroup: Identifiable, Equatable {
    let kindID: String
    let entries: [Bookmark]

    var id: String {
        kindID
    }
}

/// 书架「书签」页的状态：一次读取关注与全部书签，按维度分段。
///
/// 关注与书签分表读取，页面上「关注」固定在最前；其余按维度分段（分类 → 标签 → 未登记维度），
/// 段内保持「最近收藏在前」，同来源的条目由页面按来源顺序排在一起。
/// 不分页：量级有限，一次读取交给 `LazyVStack` 只构建可见胶囊。
@Observable
@MainActor
final class BookmarksViewModel {
    private(set) var followings: [Following] = []
    private(set) var groups: [BookmarkGroup] = []
    private(set) var loadState: InitialLoadState<BookmarksDisplayError> = .idle

    @ObservationIgnored private let bookmarkStore: BookmarkStore

    @ObservationIgnored private let followingStore: FollowingStore

    @ObservationIgnored private var loadTask: Task<Void, Never>?

    /// 变更通知的订阅（书签与关注各一条）；放在模型里而不是视图 `.task`，
    /// 避免切走书架 tab 时订阅被取消、错过后台写入。
    @ObservationIgnored private var changeTasks: [Task<Void, Never>] = []

    /// 合并短时间内的多次写入：连续翻页、批量删除只会触发一次刷新。
    @ObservationIgnored private let refreshDebouncer = Debouncer()

    /// 写操作串行队列：上一次落盘失败触发的重读不会插到下一次写入之前。
    ///
    /// operation 里只能同步地发起 `refresh()`（它自己创建任务）；不要在 operation 内 `await` 刷新结果——刷新会先 `await
    /// mutationTail`，也就是当前这个写任务本身，会形成环。
    @ObservationIgnored private var mutationTail: Task<Void, Never>?

    @ObservationIgnored private var generation = 0

    /// 页面是否可见；不可见时保存通知只记脏、不查库。
    @ObservationIgnored private var isActive = true
    @ObservationIgnored private var hasPendingChange = false

    init(bookmarkStore: BookmarkStore, followingStore: FollowingStore) {
        self.bookmarkStore = bookmarkStore
        self.followingStore = followingStore
    }

    deinit {
        loadTask?.cancel()
        changeTasks.forEach { $0.cancel() }
    }

    /// 关注与书签都为空；页面据此显示空态。
    var isEmpty: Bool {
        followings.isEmpty && groups.isEmpty
    }

    /// 开始观察变更：书签与关注的写入都会让列表重读；页面不可见时只记脏，切回补读。
    ///
    /// 普通写入由 SwiftData 在 `save()` 时自动发通知；批量写不发，由写方补一次
    /// （见 `PersistentChangeSignal.postBatchChange`）。
    func startObservingChanges() {
        guard changeTasks.isEmpty else {
            return
        }

        let entities = [PersistentChangeSignal.Entity.bookmark, PersistentChangeSignal.Entity.following]
        changeTasks = entities.map { entity in
            Task { [weak self] in
                for await _ in PersistentChangeSignal.changes(entityName: entity) {
                    guard let self else {
                        return
                    }

                    scheduleRefresh()
                }
            }
        }
    }

    /// 由视图在 `.task(id:)` 里同步可见性：切走暂停刷新，切回补一次。
    func setActive(_ active: Bool) {
        isActive = active
        guard active, hasPendingChange else { return }

        hasPendingChange = false
        refresh()
    }

    /// 300 毫秒内的多次写入合并成一次刷新：连续保存只重读一次。
    private func scheduleRefresh() {
        guard isActive else {
            hasPendingChange = true
            refreshDebouncer.cancel()
            return
        }

        refreshDebouncer.schedule { [weak self] in
            guard let self else { return }

            // 排队期间切走了：不查库，切回时由 `setActive(true)` 补读。
            guard isActive else {
                hasPendingChange = true
                return
            }

            refresh()
        }
    }

    /// 读取关注与书签；已加载过（包括空结果）的刷新保持当前展示，避免切回该分区时闪骨架。
    func refresh() {
        loadTask?.cancel()
        generation &+= 1
        let generation = generation
        let pendingMutation = mutationTail

        if isEmpty, loadState != .loaded {
            loadState = .loading
        }

        loadTask = Task { [weak self] in
            guard let self else { return }

            // 等正在落盘的删除／清空结束，避免刚删掉的条目被这次读取重新带回来。
            await pendingMutation?.value
            guard generation == self.generation else { return }

            do {
                async let bookmarks = bookmarkStore.entries()
                async let following = followingStore.entries()
                let (entries, follows) = try await (bookmarks, following)
                guard generation == self.generation else { return }

                let grouped = Self.group(entries)
                if follows != followings {
                    followings = follows
                }
                if grouped != groups {
                    groups = grouped
                }
                loadState = .loaded
            } catch {
                guard generation == self.generation else { return }

                AppLogger.warning(
                    "书签收藏读取失败，errorType=\(type(of: error))",
                    category: "Bookmarks",
                )

                // 已有内容时保留当前展示，不让一次后台刷新失败把整页换成错误页。
                if isEmpty {
                    loadState = .failed(.loadFailed)
                } else {
                    loadState = .loaded
                }
            }
        }
    }

    /// 删除一条书签：先带动画本地移除（剩余胶囊平滑回流），再落盘；失败提示并重读。
    func remove(_ bookmark: Bookmark) {
        invalidateInFlightLoads()
        withAnimation(.snappy) {
            groups = groups.compactMap { group in
                // 按身份键过滤：payload 不参与身份，重收藏后两者可能不同。
                let entries = group.entries.filter { $0.identity != bookmark.identity }
                return entries.isEmpty
                    ? nil
                    : BookmarkGroup(kindID: group.kindID, entries: entries)
            }
        }

        enqueueMutation { [weak self] in
            guard let self else { return }

            do {
                try await bookmarkStore.remove(bookmark)
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

    /// 删除一条关注：先本地移除，再落盘；失败提示并重读。
    func unfollow(_ following: Following) {
        invalidateInFlightLoads()
        withAnimation(.snappy) {
            followings.removeAll { $0.identity == following.identity }
        }

        enqueueMutation { [weak self] in
            guard let self else { return }

            do {
                try await followingStore.remove(following)
            } catch {
                AppLogger.warning(
                    "删除关注失败，errorType=\(type(of: error))",
                    category: "Bookmarks",
                )
                ToastCenter.shared.show("删除失败，请稍后重试", type: .error)
                refresh()
            }
        }
    }

    /// 清空一个维度（分类或标签）的全部收藏，跨来源。
    func clear(kindID: String) {
        invalidateInFlightLoads()
        withAnimation(.snappy) {
            groups.removeAll { $0.kindID == kindID }
        }

        enqueueMutation { [weak self] in
            guard let self else { return }

            do {
                try await bookmarkStore.removeAll(kindID: kindID)
            } catch {
                AppLogger.warning(
                    "书签维度清除失败，kind=\(kindID) errorType=\(type(of: error))",
                    category: "Bookmarks",
                )
                ToastCenter.shared.show("清除失败，请稍后重试", type: .error)
                refresh()
            }
        }
    }

    /// 清空全部关注。
    func clearFollowings() {
        invalidateInFlightLoads()
        withAnimation(.snappy) {
            followings = []
        }

        enqueueMutation { [weak self] in
            guard let self else { return }

            do {
                try await followingStore.removeAll()
            } catch {
                AppLogger.warning(
                    "关注清除失败，errorType=\(type(of: error))",
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

    /// 按维度分组：分类 → 标签 → 未登记维度（按标识排序）；段内保持读取顺序（最近收藏在前）。
    private static func group(_ entries: [Bookmark]) -> [BookmarkGroup] {
        var grouped: [String: [Bookmark]] = [:]

        for entry in entries {
            grouped[entry.kindID, default: []].append(entry)
        }

        return grouped.keys
            .sorted { lhs, rhs in
                let left = rank(lhs)
                let right = rank(rhs)
                return left == right ? lhs < rhs : left < right
            }
            .compactMap { kindID in
                grouped[kindID].map { BookmarkGroup(kindID: kindID, entries: $0) }
            }
    }

    /// 维度展示顺序：分类、标签，其余排在后面。
    private static func rank(_ kindID: String) -> Int {
        if kindID == ComicTagKind.category.id {
            return 0
        }
        if kindID == ComicTagKind.tag.id {
            return 1
        }

        return 2
    }
}

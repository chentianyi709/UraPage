import Observation
import SwiftUI

/// 书签页可展示的加载错误。
enum BookmarksDisplayError: Equatable, Sendable {
    case loadFailed

    var message: String {
        "无法读取本地书签收藏，请稍后重试"
    }
}

/// 书架「书签」页的一组内容：同一维度的收藏，组内保持最近收藏在前。
struct BookmarksSection: Identifiable {
    let kind: BookmarkKind
    let entries: [Bookmark]

    var id: String {
        kind.rawValue
    }
}

/// 书架「书签」页的状态：读取全部收藏并按维度分组，删除时本地先动、失败再重读。
@Observable
@MainActor
final class BookmarksViewModel {
    private(set) var sections: [BookmarksSection] = []
    private(set) var loadState: InitialLoadState<BookmarksDisplayError> = .idle

    @ObservationIgnored private let store: BookmarkStore
    @ObservationIgnored private var loadTask: Task<Void, Never>?
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

        if sections.isEmpty, loadState != .loaded {
            loadState = .loading
        }

        loadTask = Task { [weak self] in
            guard let self else { return }

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
                let entries = section.entries.filter { $0 != bookmark }
                return entries.isEmpty ? nil : BookmarksSection(kind: section.kind, entries: entries)
            }
        }

        Task {
            do {
                try await store.remove(bookmark)
            } catch {
                AppLogger.warning(
                    "书签收藏删除失败，errorType=\(type(of: error))",
                    category: "Bookmarks",
                )
                ToastCenter.shared.show("删除失败，请稍后重试", type: .error)
                refresh()
            }
        }
    }

    /// 清空一个维度：先带动画整组移除（下方分组上移补位），再落盘；失败提示并重读。
    func clear(_ kind: BookmarkKind) {
        invalidateInFlightLoads()
        withAnimation(.snappy) {
            sections.removeAll { $0.kind == kind }
        }

        Task {
            do {
                try await store.removeAll(kind: kind)
            } catch {
                AppLogger.warning(
                    "书签分组清除失败，kind=\(kind.rawValue) errorType=\(type(of: error))",
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

    /// 按维度分组；空维度不出现，顺序固定为作者／分类／标签。
    private static func group(_ entries: [Bookmark]) -> [BookmarksSection] {
        BookmarkKind.allCases.compactMap { kind in
            let entries = entries.filter { $0.kind == kind }
            return entries.isEmpty ? nil : BookmarksSection(kind: kind, entries: entries)
        }
    }
}

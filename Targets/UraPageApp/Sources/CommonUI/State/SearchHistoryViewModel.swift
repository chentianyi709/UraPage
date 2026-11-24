import Foundation
import Observation
import SwiftUI

/// 搜索页的搜索历史状态：每个搜索页一个，只读写本源的历史（三来源互不通用）。
///
/// 两个分区都以库里的快照为准：读写都应用同一次读取的 `SearchHistorySnapshot`，
/// 并用 generation 丢弃被后续操作取代的旧结果，避免读库与写入交错时同一个词出现在两处或状态回退。
@MainActor
@Observable
final class SearchHistoryViewModel {
    /// 本源的历史关键词，最近在前。
    private(set) var queries: [String] = []

    /// 本源的收藏词，按收藏先后排列（新收藏追加到末尾）。
    private(set) var favorites: [String] = []

    let sourceID: ComicSourceID

    @ObservationIgnored private let store: SearchHistoryStore

    /// 状态版本：每次读或写开始时递增，被后续操作取代的旧快照据此丢弃。
    @ObservationIgnored private var stateGeneration = 0

    init(store: SearchHistoryStore, sourceID: ComicSourceID) {
        self.store = store
        self.sourceID = sourceID
    }

    /// 两个分区都为空；搜索页据此隐藏整个历史区，避免空 `VStack` 占位。
    var isEmpty: Bool {
        queries.isEmpty && favorites.isEmpty
    }

    /// 读取本源的历史与收藏：一次取同一次读取的快照，两个分区不会来自不同时间点。
    func load() async {
        let generation = beginOperation()
        do {
            let snapshot = try await store.snapshot(for: sourceID)
            apply(snapshot, ifGeneration: generation, animated: false)
        } catch {
            AppLogger.warning("搜索历史读取失败，errorType=\(type(of: error))", category: "Search.History")
        }
    }

    /// 收藏一个词：落盘后按库里的快照更新两个分区。
    ///
    /// 先在菜单动作里同步改视图会移除菜单的来源视图，SwiftUI 在菜单收起过程中可能丢掉这次更新
    /// （表现为「点了没反应、再点一下才好」）；这里先 await 一次落盘，让菜单收起与列表更新错开。
    func favorite(_ query: String) async {
        guard queries.contains(query) else { return }

        let generation = beginOperation()
        do {
            let snapshot = try await store.setFavorited(true, sourceID: sourceID, query: query)
            apply(snapshot, ifGeneration: generation, animated: true)
        } catch {
            AppLogger.warning("搜索词收藏失败，errorType=\(type(of: error))", category: "Search.History")
        }
    }

    /// 取消收藏：落盘后回到「最近搜索」，按库里的搜索时间排位。
    func unfavorite(_ query: String) async {
        guard favorites.contains(query) else { return }

        let generation = beginOperation()
        do {
            let snapshot = try await store.setFavorited(false, sourceID: sourceID, query: query)
            apply(snapshot, ifGeneration: generation, animated: true)
        } catch {
            AppLogger.warning("取消收藏失败，errorType=\(type(of: error))", category: "Search.History")
        }
    }

    /// 记录一次搜索：以落盘后的快照为准；收藏词只刷新搜索时间，不会进入「最近搜索」。
    ///
    /// 搜索提交后页面切到结果区，历史不可见，不做本地乐观更新；这样收藏镜像过期时
    /// 也不会把已收藏词插进「最近搜索」。
    func record(_ query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let generation = beginOperation()
        do {
            let snapshot = try await store.record(sourceID: sourceID, query: trimmed)
            apply(snapshot, ifGeneration: generation, animated: false)
        } catch {
            AppLogger.warning("搜索历史写入失败，errorType=\(type(of: error))", category: "Search.History")
        }
    }

    /// 删除一条历史：先带动画本地移除（剩余胶囊平滑回流），再落盘并按快照校正。
    ///
    /// 落盘失败时不回滚这次本地移除——该动作通常意味着用户不想再看到它，随后再次进入页面 `load()` 会以库为准恢复。
    ///
    /// 动画包在移除这一步而不是调用方：`remove` 是异步方法，调用方在 `Task` 外层的
    /// `withAnimation` 包不到 `await` 之后的变更，动画会跑完才轮到列表更新。
    func remove(_ query: String) async {
        let generation = beginOperation()
        withAnimation(.snappy) {
            queries.removeAll { $0 == query }
        }

        do {
            let snapshot = try await store.remove(sourceID: sourceID, query: query)
            apply(snapshot, ifGeneration: generation, animated: false)
        } catch {
            AppLogger.warning("搜索历史删除失败，errorType=\(type(of: error))", category: "Search.History")
        }
    }

    /// 清空收藏：连同记录一起删除，词不会回到「最近搜索」。
    func clearFavorites() async {
        let generation = beginOperation()
        do {
            let snapshot = try await store.clearFavorites(for: sourceID)
            apply(snapshot, ifGeneration: generation, animated: true)
        } catch {
            AppLogger.warning("清空收藏失败，errorType=\(type(of: error))", category: "Search.History")
        }
    }

    /// 清空本源的「最近搜索」；收藏的搜索词保留。
    func clear() async {
        let generation = beginOperation()
        do {
            let snapshot = try await store.clear(sourceID: sourceID)
            apply(snapshot, ifGeneration: generation, animated: false)
        } catch {
            AppLogger.warning("搜索历史清除失败，errorType=\(type(of: error))", category: "Search.History")
        }
    }

    /// 开始一次读或写：递增版本，让之前发起、尚未返回的结果失效。
    private func beginOperation() -> Int {
        stateGeneration += 1
        return stateGeneration
    }

    /// 应用库里的权威快照；期间有后发起的操作则丢弃旧结果。
    private func apply(_ snapshot: SearchHistorySnapshot, ifGeneration generation: Int, animated: Bool) {
        guard generation == stateGeneration else { return }

        if animated {
            withAnimation(.snappy) {
                apply(snapshot)
            }
        } else {
            apply(snapshot)
        }
    }

    private func apply(_ snapshot: SearchHistorySnapshot) {
        queries = snapshot.queries
        favorites = snapshot.favorites
    }
}

extension EnvironmentValues {
    /// 搜索历史进程级入口存储槽；写入用 `\.searchHistoryStoreStorage`（写入路径先读缺省，缺省必须可读）。
    @Entry var searchHistoryStoreStorage: SearchHistoryStore?

    /// 读取入口：由 App 入口安装，未安装即暴露装配错误。
    var searchHistoryStore: SearchHistoryStore {
        guard let searchHistoryStoreStorage else {
            preconditionFailure("searchHistoryStore 未由 App 入口安装")
        }

        return searchHistoryStoreStorage
    }
}

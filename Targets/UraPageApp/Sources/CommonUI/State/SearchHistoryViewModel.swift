import Foundation
import Observation
import SwiftUI

/// 搜索页的搜索历史状态：每个搜索页一个，只读写本源的历史（三来源互不通用）。
@MainActor
@Observable
final class SearchHistoryViewModel {
    /// 本源的历史关键词，最近在前。
    private(set) var queries: [String] = []

    let sourceID: ComicSourceID

    @ObservationIgnored private let store: SearchHistoryStore

    init(store: SearchHistoryStore, sourceID: ComicSourceID) {
        self.store = store
        self.sourceID = sourceID
    }

    /// 读取本源历史。
    func load() async {
        do {
            queries = try await store.queries(for: sourceID)
        } catch {
            AppLogger.warning("搜索历史读取失败，errorType=\(type(of: error))", category: "Search.History")
        }
    }

    /// 记录一次搜索：先本地乐观置顶（去重、裁剪），再落盘；失败时下次读取会纠正。
    func record(_ query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        applyLocally(trimmed)
        do {
            try await store.record(sourceID: sourceID, query: trimmed)
        } catch {
            AppLogger.warning("搜索历史写入失败，errorType=\(type(of: error))", category: "Search.History")
        }
    }

    /// 删除一条历史：先带动画本地移除（剩余胶囊平滑回流），再落盘；失败时下次读取会纠正。
    ///
    /// 动画包在移除这一步而不是调用方：`remove` 是异步方法，调用方在 `Task` 外层的
    /// `withAnimation` 包不到 `await` 之后的变更，动画会跑完才轮到列表更新。
    func remove(_ query: String) async {
        withAnimation(.snappy) {
            queries.removeAll { $0 == query }
        }

        do {
            try await store.remove(sourceID: sourceID, query: query)
        } catch {
            AppLogger.warning("搜索历史删除失败，errorType=\(type(of: error))", category: "Search.History")
        }
    }

    /// 清空本源历史。
    func clear() async {
        do {
            try await store.clear(sourceID: sourceID)
            queries = []
        } catch {
            AppLogger.warning("搜索历史清除失败，errorType=\(type(of: error))", category: "Search.History")
        }
    }

    /// 把关键词移到最前并裁剪到上限（乐观更新）。
    private func applyLocally(_ query: String) {
        queries.removeAll { $0 == query }
        queries.insert(query, at: 0)

        let limit = AppConfiguration.SearchHistory.maxEntriesPerSource
        if queries.count > limit {
            queries.removeLast(queries.count - limit)
        }
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

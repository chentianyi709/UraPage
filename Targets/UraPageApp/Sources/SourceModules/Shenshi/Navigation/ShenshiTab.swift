import Foundation

/// 绅士固定的 Tab 名称、图标与顺序。
enum ShenshiTab: SourceTabValue, CaseIterable, Identifiable {
    /// 本源稳定标识。
    var sourceID: ComicSourceID {
        .shenshi
    }

    case recommended
    case updates
    case ranking
    case search
    case library

    /// 使用 Tab 自身作为 SwiftUI 列表的稳定标识。
    var id: Self {
        self
    }

    /// Tab 的固定显示名称。
    var title: String {
        switch self {
        case .recommended: "推荐"
        case .updates: "更新"
        case .ranking: "排行"
        case .search: "搜索"
        case .library: "书架"
        }
    }

    /// Tab 的固定 SF Symbol。
    var systemImage: String {
        switch self {
        case .recommended: "star"
        case .updates: "clock"
        case .ranking: "chart.bar"
        case .search: "magnifyingglass"
        case .library: "books.vertical"
        }
    }
}

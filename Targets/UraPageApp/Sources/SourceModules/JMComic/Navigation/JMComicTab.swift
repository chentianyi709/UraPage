import Foundation

/// 禁漫固定的 Tab 名称、图标与顺序。
enum JMComicTab: SourceTabValue, CaseIterable, Identifiable {
    /// 本源稳定标识。
    var sourceID: ComicSourceID {
        .jm
    }

    case home
    case latest
    case categories
    case search
    case library

    /// 使用 Tab 自身作为 SwiftUI 列表的稳定标识。
    var id: Self {
        self
    }

    /// Tab 的固定显示名称。
    var title: String {
        switch self {
        case .home: "首页"
        case .latest: "最新"
        case .categories: "分类"
        case .search: "搜索"
        case .library: "书架"
        }
    }

    /// Tab 的固定 SF Symbol。
    var systemImage: String {
        switch self {
        case .home: "house"
        case .latest: "clock"
        case .categories: "square.grid.2x2"
        case .search: "magnifyingglass"
        case .library: "books.vertical"
        }
    }
}

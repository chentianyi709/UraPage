import SwiftUI

/// 详情作者或标签打开的固定关键词结果页；复用搜索页的分页状态和结果网格。
struct JMComicQueryComicsView: View {
    @Environment(\.jmComicServices) private var services

    @State private var model: JMComicSearchModel?

    let query: String
    let searchType: JMComicSearchType
    let bookmarkKind: ComicTagKind

    init(query: String, searchType: JMComicSearchType = .site, bookmarkKind: ComicTagKind) {
        self.query = query
        self.searchType = searchType
        self.bookmarkKind = bookmarkKind
    }

    /// 同一页承载作者查询与标签查询，收藏维度由进入时的调用方显式给出。
    private var bookmark: Bookmark {
        Bookmark(
            sourceID: .jm,
            kind: bookmarkKind,
            displayName: query,
            value: query,
        )
    }

    var body: some View {
        ZStack {
            Color.pageBackground.ignoresSafeArea()

            if let model {
                JMComicSearchResultsView(model: model, emptyIllustration: .empty)
            } else {
                ComicGridSkeletonView()
            }
        }
        .navigationTitle(query)
        .toolbarTitleDisplayMode(.inline)
        .toolbar {
            // 与公共列表页一致：收藏与排序菜单各占一个工具栏项，中间用 `ToolbarSpacer` 隔开——
            // 相邻的工具栏项会被系统并成同一颗玻璃胶囊，必须有间隔才是两个独立的圆按钮。
            ToolbarItem(placement: .topBarTrailing) {
                BookmarkButton(bookmark: bookmark)
            }

            ToolbarSpacer(.fixed, placement: .topBarTrailing)

            ToolbarItem(placement: .topBarTrailing) {
                SelectionMenu(
                    items: JMComicSearchSort.allCases.map { sort in
                        SelectionMenuItem(id: sort.rawValue, title: sort.displayTitle)
                    },
                    selectedID: model?.sort.rawValue ?? JMComicSearchSort.latest.rawValue,
                    defaultID: JMComicSearchSort.latest.rawValue,
                    isLoading: false,
                    systemImage: "line.3.horizontal.decrease",
                    accessibilityLabel: "切换作品排序",
                    loadingAccessibilityLabel: "正在加载作品排序",
                    onSelect: { selectionID in
                        if let sort = JMComicSearchSort.allCases
                            .first(where: { $0.rawValue == selectionID }) {
                            model?.selectSort(sort)
                        }
                    },
                )
            }
        }
        .task {
            guard model == nil else { return }

            let model = JMComicSearchModel(services: services)
            model.selectSearchType(searchType)
            model.searchText = query
            self.model = model
            model.submitSearch()
        }
    }
}

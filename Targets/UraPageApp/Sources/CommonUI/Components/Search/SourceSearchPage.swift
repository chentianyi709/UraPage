import SwiftUI

/// 来源搜索页骨架：标题、导航栏搜索框、提交与清空的联动，以及「未搜索 → 引导区／已搜索 → 结果区」的切换。
///
/// 只编排三处搜索页逐字相同的部分；搜索条件（工具栏菜单或弹窗）、引导内容与结果数据源都是槽位，
/// 由来源提供：哔咔的工具栏是排序＋分类筛选、引导区是热门搜索词，禁漫是四个条件菜单，绅士两者都没有。
/// 搜索框文本仍由来源的状态 owner 持有，这里只绑定与联动，不新建状态。
struct SourceSearchPage<Toolbar: ToolbarContent, Idle: View, Results: View>: View {
    /// 搜索框文本；来源用状态 owner 派生的绑定传入（owner 尚未创建时为空串）。
    @Binding var searchText: String

    /// 回车提交搜索。
    let onSubmit: () -> Void

    /// 搜索框被清空（含系统清空按钮）；来源据此回到引导态。
    let onClear: () -> Void

    /// 是否已提交过搜索：`true` 显示结果区，`false` 显示引导区。
    let isSearching: Bool

    let toolbar: () -> Toolbar
    let idle: () -> Idle
    let results: () -> Results

    /// 搜索框焦点：搜索动作触发后收回键盘，避免键盘遮挡结果区（点击热门词／历史词时尤其明显）。
    @FocusState private var isSearchFieldFocused: Bool

    /// 由来源给出工具栏与两个状态区；三处槽位都用结果构造器，调用方可直接写多行内容。
    init(
        searchText: Binding<String>,
        onSubmit: @escaping () -> Void,
        onClear: @escaping () -> Void,
        isSearching: Bool,
        @ContentBuilder toolbar: @escaping () -> Toolbar,
        @ContentBuilder idle: @escaping () -> Idle,
        @ContentBuilder results: @escaping () -> Results,
    ) {
        _searchText = searchText
        self.onSubmit = onSubmit
        self.onClear = onClear
        self.isSearching = isSearching
        self.toolbar = toolbar
        self.idle = idle
        self.results = results
    }

    var body: some View {
        ZStack {
            Color.pageBackground.ignoresSafeArea()

            if isSearching {
                results()
            } else {
                idle()
            }
        }
        .inlineLargeNavigationTitle("搜索")
        .toolbar {
            toolbar()
        }
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "搜索漫画",
        )
        .searchFocused($isSearchFieldFocused)
        .searchPresentationToolbarBehavior(.avoidHidingContent)
        .onSubmit(of: .search) {
            // 键盘搜索键提交（含结果区里改词重搜）后收起键盘。
            isSearchFieldFocused = false
            onSubmit()
        }
        .onChange(of: isSearching) { _, isSearching in
            // 点击热门搜索词或历史词直接进入结果区、不经过系统提交，这里统一收起键盘。
            guard isSearching else {
                return
            }

            isSearchFieldFocused = false
        }
        .onChange(of: searchText) { _, searchText in
            guard searchText.isEmpty else {
                return
            }

            onClear()
        }
    }
}

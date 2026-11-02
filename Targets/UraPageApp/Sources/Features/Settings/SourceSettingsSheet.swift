import SwiftUI

/// 来源设置弹窗内的一个来源自定义分页：typed 值 + 展示名称与图标。
struct SourceSettingsTabItem<Value: Hashable> {
    let value: Value
    let title: String
    let systemImage: String
}

/// 来源设置弹窗的分页：来源自定义分页在前，通用设置固定最后。
///
/// 通用设置由公共层提供（所有来源一致，包括将来的来源），来源只声明自己的分页，
/// 因此不需要也不可能把它排到别处。
enum SourceSettingsPage<SourceTab: Hashable>: Hashable {
    case source(SourceTab)
    case general
}

/// 通用设置分页固定的展示名称与图标（所有来源一致）。
private let generalPageTitle = "通用设置"
private let generalPageSystemImage = "gearshape"

/// 来源设置弹窗的常见分页（当前各来源一致）：个人中心、漫画源设置。
///
/// `allCases` 顺序即 TabBar 展示顺序（通用设置由公共外壳固定追加在最后）；
/// 「个人中心」在第一位，但打开弹窗时默认停在「漫画源设置」——见
/// `SourceSettingsSheet.init(sourceTabs:initialTab:sourceContent:)`。
/// 来源需要自己的分页组合时，仍然可以自行声明 typed 枚举并用 `SourceSettingsSheet(sourceTabs:)` 组装。
enum SourceSettingsTab: Hashable, CaseIterable {
    case account
    case sourceSettings

    /// 分页的展示名称。
    var title: String {
        switch self {
        case .sourceSettings:
            "漫画源设置"
        case .account:
            "个人中心"
        }
    }

    /// 分页的 SF Symbol。
    var systemImage: String {
        switch self {
        case .sourceSettings:
            "network"
        case .account:
            "person.crop.circle"
        }
    }

    /// 所有来源当前共用的标准分页描述；来源仍自行提供每页内容。
    static var items: [SourceSettingsTabItem<Self>] {
        allCases.map { tab in
            SourceSettingsTabItem(value: tab, title: tab.title, systemImage: tab.systemImage)
        }
    }
}

/// 当前所有来源共用的标准内容：来源自己的「漫画源设置」页 + 来源自己的账号页。
///
/// 来源 Module 提供两页内容；将来某个来源的分页结构真正分化时，
/// 它仍可直接使用 `SourceSettingsSheet(sourceTabs:)` 组装自己的 typed 分页。
struct StandardSourceSettingsContent<SourceSettingsContent: View, AccountContent: View>: View {
    let tab: SourceSettingsTab
    let sourceSettingsContent: SourceSettingsContent
    let accountContent: AccountContent

    init(
        tab: SourceSettingsTab,
        @ContentBuilder _ sourceSettingsContent: () -> SourceSettingsContent,
        @ContentBuilder account accountContent: () -> AccountContent,
    ) {
        self.tab = tab
        self.sourceSettingsContent = sourceSettingsContent()
        self.accountContent = accountContent()
    }

    var body: some View {
        switch tab {
        case .sourceSettings:
            sourceSettingsContent

        case .account:
            accountContent
        }
    }
}

/// 当前所有来源一致的标准设置弹窗：漫画源设置 + 个人中心，通用设置由外壳追加到最后。
///
/// 来源只提供两页内容；分页结构或默认停留页真正分化时，来源仍可直接组装
/// `SourceSettingsSheet(sourceTabs:initialTab:sourceContent:)`。
@MainActor
func standardSourceSettingsSheet(
    @ContentBuilder sourceSettingsContent: @escaping () -> some View,
    @ContentBuilder account accountContent: @escaping () -> some View,
) -> some View {
    SourceSettingsSheet(
        sourceTabs: SourceSettingsTab.items,
        initialTab: .sourceSettings,
    ) { tab in
        StandardSourceSettingsContent(tab: tab) {
            sourceSettingsContent()
        } account: {
            accountContent()
        }
    }
}

/// 来源设置弹窗外壳（公共）：系统 TabView + 每个分页内嵌导航栏与关闭按钮。
///
/// 与旧项目一致：`4/5` 高度（可拉到全屏）、拖拽指示、内容背景跟随主题；
/// 只有通用设置一个分页时不显示 TabBar。来源只提供自定义分页与它们的内容，
/// 通用设置的内容由公共层给出。
///
/// 弹窗主题由呈现方统一应用（App 级弹窗见 `AppShellView.sheetContent`），因此这里不再自己套
/// `preferredColorScheme`；页面级弹窗不在该覆盖之下，需要在呈现处自行应用主题。
struct SourceSettingsSheet<SourceTab: Hashable, SourceContent: View>: View {
    @Environment(\.dismiss) private var dismiss

    /// 来源声明的分页（顺序即展示顺序，通用设置会自动追加到最后）。
    let sourceTabs: [SourceSettingsTabItem<SourceTab>]

    /// 来源分页的内容。
    @ContentBuilder let sourceContent: (SourceTab) -> SourceContent

    @State private var selectedPage: SourceSettingsPage<SourceTab>
    @State private var selectedDetent: PresentationDetent = .fraction(4 / 5)

    /// 打开时停在 `initialTab` 指定的来源分页（须存在于 `sourceTabs`）；未指定或不匹配时停在第一个
    /// 来源分页；来源没有自定义分页时只有通用设置。
    init(
        sourceTabs: [SourceSettingsTabItem<SourceTab>],
        initialTab: SourceTab? = nil,
        @ContentBuilder sourceContent: @escaping (SourceTab) -> SourceContent,
    ) {
        self.sourceTabs = sourceTabs
        self.sourceContent = sourceContent
        let initial = initialTab.flatMap { tab in
            sourceTabs.contains { $0.value == tab } ? tab : nil
        } ?? sourceTabs.first?.value
        _selectedPage = State(initialValue: initial.map { .source($0) } ?? .general)
    }

    var body: some View {
        TabView(selection: $selectedPage) {
            ForEach(pages, id: \.self) { page in
                Tab(title(for: page), systemImage: systemImage(for: page), value: page) {
                    pageContent(for: page)
                }
            }
        }
        .toolbarBackground(Color.pageBackground, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        // 只有一个分页（来源没有自定义分页）时不显示 TabBar。
        .toolbarVisibility(pages.count > 1 ? .visible : .hidden, for: .tabBar)
        .presentationDetents(
            [.fraction(4 / 5), .large],
            selection: $selectedDetent,
        )
        // sheet 形状的底色（含圆角与边缘）跟随主题；内容背景由各分页自己负责。
        .presentationBackground(Color.pageBackground)
        .presentationDragIndicator(.visible)
    }

    /// 分页顺序：来源自定义分页 + 固定最后的通用设置。
    private var pages: [SourceSettingsPage<SourceTab>] {
        sourceTabs.map { .source($0.value) } + [.general]
    }

    private func title(for page: SourceSettingsPage<SourceTab>) -> String {
        switch page {
        case let .source(tab):
            sourceTabs.first { $0.value == tab }?.title ?? ""
        case .general:
            generalPageTitle
        }
    }

    private func systemImage(for page: SourceSettingsPage<SourceTab>) -> String {
        switch page {
        case let .source(tab):
            sourceTabs.first { $0.value == tab }?.systemImage ?? "square.grid.2x2"
        case .general:
            generalPageSystemImage
        }
    }

    /// 每个分页保留导航标题与关闭按钮；导航栏背景隐藏，只留内容背景。
    private func pageContent(for page: SourceSettingsPage<SourceTab>) -> some View {
        NavigationStack {
            content(for: page)
                .navigationTitle(title(for: page))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(action: dismiss.callAsFunction) {
                            Image(systemName: "xmark")
                                .foregroundStyle(Color.textPrimary)
                        }
                        .tint(Color.textPrimary)
                        .accessibilityLabel("关闭")
                    }
                }
                .toolbarBackground(.hidden, for: .navigationBar)
        }
        .appNavigationBarScrollEdgeEffect()
    }

    @ContentBuilder
    private func content(for page: SourceSettingsPage<SourceTab>) -> some View {
        switch page {
        case let .source(tab):
            sourceContent(tab)

        case .general:
            GeneralSettingsView()
        }
    }
}

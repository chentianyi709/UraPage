import SwiftUI

/// 详情页工具栏「更多操作」菜单的一项。
///
/// 菜单长什么样（图标、分组、破坏性样式）由公共层统一，具体做什么由页面给出的 `action` 决定；
/// 菜单只承载当前作品／来源的次要操作，不重复底栏和内容区已有入口，不可用动作不要加入数组。
struct ComicDetailMenuAction {
    /// 菜单项标题；同时作为 VoiceOver 的朗读文案。
    let title: String

    /// 菜单项左侧的 SF Symbol。
    let systemImage: String

    /// 破坏性动作交给系统染红；其余动作保持正文色。
    var isDestructive: Bool = false

    /// 在上一项之后插入分割线；第一项忽略。
    var showsDividerBefore: Bool = false

    /// 选中后执行的动作。
    let action: @MainActor () -> Void
}

/// 详情页统一外壳：底色铺满、保留控件安全区、导航栏透明且不显示标题。
///
/// 顶部工具栏右侧固定展示当前作品来源的圆形 Logo（在线／离线详情共用）；
/// 来源信息读 `\.sourceDescriptor`，由来源 Module 的 destination 边界安装。
/// 传入非空 `menuActions` 时，Logo 右侧再放一个「更多」按钮（`Menu` + `ellipsis.circle`），
/// 两者中间插 `ToolbarSpacer(.fixed)` 分开排布（与来源首页的 Logo＋账号同款）；
/// 空数组时只有 Logo，不放置点了没反应的入口。
struct ComicDetailChrome<Content: View>: View {
    @Environment(\.sourceDescriptor) private var descriptor

    let title: String?

    /// 工具栏「更多操作」菜单；空数组时不显示更多按钮。
    let menuActions: [ComicDetailMenuAction]

    @ContentBuilder let content: () -> Content

    var body: some View {
        let sections = actionSections

        return ZStack {
            Color.pageBackground.ignoresSafeArea()

            content()
        }
        .ignoresSafeArea(edges: .top)
        .navigationTitle(title ?? "漫画详情")
        .toolbar(removing: .title)
        .toolbar {
            // 来源标识；只展示，不参与操作。36 与来源首页的 Logo 一致，两页大小相同。
            ToolbarItem(placement: .topBarTrailing) {
                SourceLogoView(descriptor.logo, size: 36, outline: .circle)
            }

            // 与来源首页一致：中间插固定 spacer，两项各拿一颗玻璃圆，不并成一颗胶囊。
            if !menuActions.isEmpty {
                ToolbarSpacer(.fixed, placement: .topBarTrailing)

                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        ForEach(sections.indices, id: \.self) { sectionIndex in
                            Section {
                                ForEach(sections[sectionIndex].indices, id: \.self) { index in
                                    menuButton(sections[sectionIndex][index])
                                }
                            }
                        }
                    } label: {
                        // 全局 tint 是品牌色，菜单触发件与菜单项图标都会继承成品牌红；
                        // 这里显式改回正文色（菜单项图标跟随 tint，不只是 label）。
                        Image(systemName: "ellipsis.circle")
                            .foregroundStyle(Color.textPrimary)
                    }
                    .tint(Color.textPrimary)
                    .accessibilityLabel("\(descriptor.displayName) 更多操作")
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .scrollEdgeEffectHidden(true, for: .top)
    }

    private func menuButton(_ action: ComicDetailMenuAction) -> some View {
        Button(role: action.isDestructive ? .destructive : nil, action: action.action) {
            Label(action.title, systemImage: action.systemImage)
        }
    }

    /// 按 `showsDividerBefore` 切成若干组；`Menu` 里每组一个 `Section`，组之间由系统画分隔线。
    private var actionSections: [[ComicDetailMenuAction]] {
        guard !menuActions.isEmpty else { return [] }

        var sections: [[ComicDetailMenuAction]] = [[]]

        for action in menuActions {
            if action.showsDividerBefore, !sections[sections.count - 1].isEmpty {
                sections.append([])
            }

            sections[sections.count - 1].append(action)
        }

        return sections
    }
}

extension View {
    /// 套上详情页统一外壳；`menuActions` 为空时只有来源 Logo。
    func comicDetailChrome(
        title: String?,
        menuActions: [ComicDetailMenuAction] = [],
    ) -> some View {
        ComicDetailChrome(
            title: title,
            menuActions: menuActions,
        ) { self }
    }
}

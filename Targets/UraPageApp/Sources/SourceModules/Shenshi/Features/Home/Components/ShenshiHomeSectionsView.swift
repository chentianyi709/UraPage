import SwiftUI

/// 绅士推荐首页的分区内容：纵向分区，每个分区一个标题 + 固定三列的两行卡片。
///
/// 复用公共网格度量与卡片；分区标题按来源解析出的 typed 跳转语义决定是否可点。
struct ShenshiHomeSectionsView: View {
    let sections: [ShenshiHomeSection]
    let onSelectComic: (ComicListItem) -> Void

    /// 点击带更新语义的分区标题；`nil` 表示全部更新。
    let onSelectUpdates: (Int?) -> Void

    var body: some View {
        GeometryReader { proxy in
            let itemWidth = ComicGridMetrics.itemWidth(for: proxy.size.width)

            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 24) {
                    ForEach(sections) { section in
                        sectionView(section, itemWidth: itemWidth)
                    }
                }
                .padding(.vertical, ComicGridMetrics.verticalPadding)
            }
            .scrollToTopButton()
        }
    }

    /// 单个分区：标题 + 该分区的三列网格（服务端每个分区最多给出六个条目）。
    private func sectionView(_ section: ShenshiHomeSection, itemWidth: CGFloat) -> some View {
        ComicSection {
            sectionHeader(section)
        } content: {
            LazyVGrid(
                columns: ComicGridMetrics.columns(itemWidth: itemWidth),
                alignment: .center,
                spacing: ComicGridMetrics.rowSpacing,
            ) {
                ForEach(section.items) { item in
                    ComicCardView(item: item, itemWidth: itemWidth) { selected in
                        onSelectComic(selected)
                    }
                }
            }
            .padding(.horizontal, ComicGridMetrics.horizontalPadding)
        }
    }

    /// 分区标题：有更新跳转语义时是整行按钮（显示箭头提示），否则只展示文案。
    @ContentBuilder
    private func sectionHeader(_ section: ShenshiHomeSection) -> some View {
        switch section.navigation {
        case let .updates(categoryID):
            ComicSectionHeaderButton(
                title: section.title,
                accessibilityHint: categoryID == nil
                    ? "切换到全部更新页面"
                    : "切换到更新页面并显示该分类",
            ) {
                onSelectUpdates(categoryID)
            }

        case .none:
            ComicSectionHeader(title: section.title, showsDisclosureIndicator: false)
        }
    }
}

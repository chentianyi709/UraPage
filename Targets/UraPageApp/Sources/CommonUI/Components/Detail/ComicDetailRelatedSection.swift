import SwiftUI

/// 详情页相关推荐分区：标题固定为「相关推荐」，内容为三列普通漫画卡片；空列表不显示分区。
///
/// 点击只回传作品身份；来源详情页使用本源路由打开对应作品。
struct ComicDetailRelatedContent: View {
    /// 来源详情已同步提供的相关作品。
    let comics: [ComicListItem]

    /// 点击某张卡片。
    let onSelect: (ComicIdentity) -> Void

    var body: some View {
        if !comics.isEmpty {
            ComicDetailSection(title: "相关推荐", systemImage: "sparkles") {
                ComicDetailRelatedWidthReader { contentWidth in
                    ComicEagerGrid(
                        comics: comics,
                        itemWidth: ComicGridMetrics.itemWidth(forAvailableWidth: contentWidth),
                        onSelect: { item in onSelect(item.identity) },
                    )
                }
            }
        }
    }
}

/// 详情页相关推荐占位网格；与真实推荐一样使用非惰性布局，避免简介收起时位移滞后。
struct ComicDetailRelatedSkeletonGrid: View {
    var body: some View {
        ComicDetailRelatedWidthReader { contentWidth in
            let itemWidth = ComicGridMetrics.itemWidth(forAvailableWidth: contentWidth)

            Grid(
                alignment: .leading,
                horizontalSpacing: ComicGridMetrics.gridSpacing,
                verticalSpacing: ComicGridMetrics.rowSpacing,
            ) {
                ForEach(0 ..< 2, id: \.self) { _ in
                    GridRow {
                        ForEach(0 ..< ComicGridMetrics.columnCount, id: \.self) { _ in
                            ComicCardSkeletonView(itemWidth: itemWidth)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// 只测量分区父容器给出的宽度；测量目标不含网格，避免列宽反过来影响测量值。
private struct ComicDetailRelatedWidthReader<Content: View>: View {
    @State private var contentWidth: CGFloat = 0

    @ContentBuilder let content: (CGFloat) -> Content

    var body: some View {
        VStack(spacing: 0) {
            Color.clear
                .frame(height: 0)
                .frame(maxWidth: .infinity)
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { contentWidth = $0 }

            content(contentWidth)
        }
        .frame(maxWidth: .infinity)
    }
}

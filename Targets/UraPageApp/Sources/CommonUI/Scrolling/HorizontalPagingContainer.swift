import SwiftUI

/// 横向分页容器：用系统分页滚动承载 typed 页面，并同步选中页与连续进度。
///
/// 与工具栏标签切换组件是**两个独立组件**：这里只负责页面左右滑动，
/// 标签组件用 `selectionProgress` 跟随滑动；两者通过页面持有的
/// `selectedPage`／`pageScrollID`／`selectionProgress` 三个状态联动，也可以各自单独使用。
///
/// 只在分页滚动稳定（`phase == .idle`）后提交 `selectedPage`：滑动途经的页面不产生业务选择，
/// 避免中途触发页面数据加载或状态切换。
///
/// 页面用 `HStack` 常驻而不是 `LazyHStack`：使用方都是少量固定页面（书架 3 页、排行榜 4 页），
/// 常驻才能保留每页的 `@State`（模型、已加载数据）与滚动位置；懒加载会在页面离屏后释放视图，
/// 切回来时模型重建、数据重读、位置回到顶部，看起来就是“切个标签就重新加载”。
struct HorizontalPagingContainer<Page: Hashable, Content: View>: View {
    /// 依次展示的页面。
    let pages: [Page]

    /// 当前选中页；由分页稳定结果驱动（点击标签时由调用方直接赋值）。
    @Binding var selectedPage: Page

    /// 滚动位置绑定的页面 identity；点击标签切换页时由调用方赋值。
    @Binding var pageScrollID: Page?

    /// 连续滑动进度（`0 ... count - 1`），供工具栏指示块跟随。
    @Binding var selectionProgress: CGFloat

    /// 每页内容。
    @ContentBuilder let content: (Page) -> Content

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 0) {
                ForEach(pages, id: \.self) { page in
                    content(page)
                        .containerRelativeFrame(.horizontal)
                        .id(page)
                }
            }
            .scrollTargetLayout()
        }
        .scrollIndicators(.hidden)
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $pageScrollID)
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            progress(for: geometry)
        } action: { _, newProgress in
            selectionProgress = newProgress
        }
        .onScrollPhaseChange { _, newPhase in
            guard newPhase == .idle else {
                return
            }

            commitSettledSelection()
        }
    }

    /// 连续进度：横向偏移除以容器宽度，并夹在有效页码范围内。
    private func progress(for geometry: ScrollGeometry) -> CGFloat {
        let pageWidth = max(geometry.containerSize.width, 1)
        let maxProgress = CGFloat(max(pages.count - 1, 0))
        return min(max(geometry.contentOffset.x / pageWidth, 0), maxProgress)
    }

    /// 分页稳定后提交选中页。
    private func commitSettledSelection() {
        guard !pages.isEmpty else {
            return
        }

        let index = min(max(Int(selectionProgress.rounded()), 0), pages.count - 1)
        let page = pages[index]
        guard selectedPage != page else {
            return
        }

        selectedPage = page
    }
}

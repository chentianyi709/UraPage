import SwiftUI

extension View {
    /// 在纵向滚动内容进入底部预取范围时发出同步信号。
    ///
    /// 只观察滚动几何信息，不保存页码，也不创建异步请求。
    func onApproachingBottom(
        prefetchScreens: CGFloat,
        action: @escaping @MainActor () -> Void,
    ) -> some View {
        modifier(BottomPrefetchModifier(prefetchScreens: prefetchScreens, action: action))
    }
}

/// 根据容器高度计算底部预取范围，并在进入范围或内容追加后通知页面。
private struct BottomPrefetchModifier: ViewModifier {
    let prefetchScreens: CGFloat
    let action: @MainActor () -> Void

    func body(content: Content) -> some View {
        content
            // 预取是“保持续载”的语义，而不是“只在状态翻转时续载一次”：
            // - 不要求 offset > 0：首屏数据不多、一开始就在范围内时也要续载，不让用户先滑一下；
            // - 不要求内容高过容器：内容不足一屏（remainingDistance 为负）时同样在范围内，
            //   否则无法滚动就永远加载不出下一页；
            // - 观察值带上内容高度：内容因追加而变高时同样触发一次（否则一直“在范围内”不会有变化，
            //   续载会在第二页后停住）。
            // 重复触发由 `ComicPagingModel` 的 `canLoadMore`/`isLoadingMore`/`loadMoreError` 守卫兜住。
            .onScrollGeometryChange(for: BottomPrefetchState.self) { geometry in
                let visibleBottom = geometry.contentOffset.y + geometry.containerSize.height
                let remainingDistance = geometry.contentSize.height - visibleBottom
                let threshold = geometry.containerSize.height * max(prefetchScreens, 0)

                return BottomPrefetchState(
                    isApproachingBottom: remainingDistance <= threshold,
                    contentHeight: geometry.contentSize.height,
                )
            } action: { _, newState in
                guard newState.isApproachingBottom else {
                    return
                }

                action()
            }
    }
}

/// 保存是否进入预取范围与当前内容高度；内容高度让“追加后仍在范围内”也能触发一次续载。
private struct BottomPrefetchState: Equatable {
    let isApproachingBottom: Bool
    let contentHeight: CGFloat
}

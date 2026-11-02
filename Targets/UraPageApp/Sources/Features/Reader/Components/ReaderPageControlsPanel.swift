import SwiftUI

/// 在显示期间读取页码，并在隐藏动画结束后彻底卸载控制器。
///
/// 页码由闭包延迟获取：稳定隐藏期间不会读取来源 ViewModel 的高频页码状态，
/// 因而不会随 Canvas 滚动持续更新这个 SwiftUI 子树。
struct ReaderPageControlsPanel: View {
    let isVisible: Bool
    let currentPage: () -> ReaderPageSlot?
    let pageTotal: () -> Int?
    let onCommit: (Int) -> Void

    @State private var isOverlayMounted = false
    @State private var isOverlayVisible = false

    var body: some View {
        ZStack {
            if isOverlayMounted,
               let currentPage = currentPage(),
               let pageTotal = pageTotal(),
               pageTotal > 1 {
                ReaderPageControlsOverlay(
                    isVisible: isOverlayVisible,
                    currentPageNumber: currentPage.index + 1,
                    pageTotal: pageTotal,
                    onCommit: onCommit,
                )
                // 切章后拖动与预览状态属于新章节，即使加载同步完成也必须重新创建。
                .id(currentPage.identity.chapter)
                // 外壳挂载和切章不使用默认淡入淡出；玻璃仅保留内部位移／缩放过渡。
                .transition(.identity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: isVisible) {
            await updateMountState(isVisible: isVisible)
        }
    }

    /// 显示时立即挂载；隐藏时等待移出动画结束后再停止页码观察。
    /// `task(id:)` 会在状态反转或页面销毁时自动取消旧流程。
    private func updateMountState(isVisible: Bool) async {
        if isVisible {
            isOverlayMounted = true
            isOverlayVisible = false

            // 等待不可见外壳完成一次布局，再只为滑块执行移入动画。
            await Task.yield()
            guard !Task.isCancelled else {
                return
            }

            withAnimation(ReaderChromeAnimation.value) {
                isOverlayVisible = true
            }
            return
        }

        guard isOverlayMounted else {
            return
        }

        withAnimation(ReaderChromeAnimation.value) {
            isOverlayVisible = false
        }

        do {
            try await Task.sleep(
                for: .seconds(ReaderChromeAnimation.duration),
            )
        } catch {
            return
        }

        isOverlayMounted = false
    }
}

import SwiftUI

/// 管理来源无关的 Reader 页码滑块、中央预览和一次性跳页提交。
struct ReaderPageControlsOverlay: View {
    let isVisible: Bool
    let currentPageNumber: Int
    let pageTotal: Int
    let onCommit: (Int) -> Void

    @State private var sliderValue: Double
    @State private var isDragging = false
    @State private var showsIndicator = false
    @State private var indicatorValue: Int
    @State private var indicatorHideTask: Task<Void, Never>?

    /// 使用 Canvas 当前页创建稳定的滑块初始值，
    /// 避免组件出现时短暂显示第一页。
    init(
        isVisible: Bool,
        currentPageNumber: Int,
        pageTotal: Int,
        onCommit: @escaping (Int) -> Void,
    ) {
        let validTotal = max(pageTotal, 1)
        let validPageNumber = min(max(currentPageNumber, 1), validTotal)
        self.isVisible = isVisible
        self.currentPageNumber = currentPageNumber
        self.pageTotal = pageTotal
        self.onCommit = onCommit
        _sliderValue = State(initialValue: Double(validPageNumber))
        _indicatorValue = State(initialValue: validPageNumber)
    }

    var body: some View {
        GlassEffectContainer(spacing: 0) {
            ZStack {
                VStack(spacing: 0) {
                    Spacer()

                    if isVisible {
                        ReaderPageSliderControl(
                            pageTotal: pageTotal,
                            value: $sliderValue,
                            onEditingChanged: handleEditingChanged,
                            onCommit: onCommit,
                        )
                        .padding(.horizontal, 16)
                        .padding(.bottom, 62)
                        // 过渡只作用于滑块和它的底部边距。若包住全屏 VStack，
                        // 隐藏时滑块只移动很短距离便离开屏幕，视觉速度会异常快。
                        .transition(.move(edge: .bottom))
                    }
                }
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity,
                    alignment: .bottom,
                )

                if isVisible, showsIndicator {
                    ReaderPageSliderIndicator(
                        pageNumber: indicatorValue,
                        pageTotal: pageTotal,
                    )
                    .frame(
                        maxWidth: .infinity,
                        maxHeight: .infinity,
                        alignment: .center,
                    )
                    // 中央页码只做轻微缩放，不改变透明度，避免玻璃淡入淡出。
                    .transition(.scale(scale: 0.9))
                }
            }
        }
        .onChange(of: currentPageNumber) {
            synchronizeWithCurrentPageIfPossible()
        }
        .onChange(of: pageTotal) {
            synchronizeWithCurrentPageIfPossible()
        }
        .onChange(of: showsIndicator) {
            // 从最新 View 输入恢复页码，不使用一秒前创建延迟任务时的旧快照。
            synchronizeWithCurrentPageIfPossible()
        }
        .onChange(of: isVisible) { _, isVisible in
            guard !isVisible else {
                return
            }

            isDragging = false
            showsIndicator = false
            indicatorHideTask?.cancel()
            indicatorHideTask = nil
        }
        .onChange(of: sliderValue) { _, newValue in
            guard isDragging else {
                return
            }

            let pageNumber = Int(newValue.rounded())
            if indicatorValue != pageNumber {
                indicatorValue = pageNumber
            }
        }
        .onDisappear {
            indicatorHideTask?.cancel()
            indicatorHideTask = nil
        }
    }

    /// 保持中央预览一秒，然后恢复到 Canvas 实际回报的页码。
    private func handleEditingChanged(_ editing: Bool) {
        isDragging = editing
        indicatorHideTask?.cancel()
        indicatorHideTask = nil

        if editing {
            indicatorValue = Int(sliderValue.rounded())
            withAnimation(.snappy(duration: 0.2)) {
                showsIndicator = true
            }

            return
        }

        indicatorValue = Int(sliderValue.rounded())
        indicatorHideTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .seconds(1))
            } catch {
                return
            }

            withAnimation(.easeOut(duration: 0.2)) {
                showsIndicator = false
            }
        }
    }

    /// 只在用户没有拖动或查看目标页预览时，
    /// 同步 Canvas 的真实页码。
    private func synchronizeWithCurrentPageIfPossible() {
        guard !isDragging,
              !showsIndicator
        else {
            return
        }

        let validPageNumber = min(
            max(currentPageNumber, 1),
            max(pageTotal, 1),
        )
        let value = Double(validPageNumber)
        if sliderValue != value {
            sliderValue = value
        }
    }
}

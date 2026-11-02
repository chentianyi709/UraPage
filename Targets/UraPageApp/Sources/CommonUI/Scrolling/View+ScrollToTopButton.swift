import SwiftUI

extension View {
    /// 返回顶部按钮（自带滚动位置）：把当前视图当作滚动容器安装位置绑定。
    ///
    /// 滚动超过半屏后，右下角出现圆形玻璃按钮，点击带动画回到顶部；页面不需要自己持有 `ScrollPosition`。
    func scrollToTopButton() -> some View {
        modifier(ScrollToTopButtonModifier(position: nil))
    }

    /// 返回顶部按钮（复用页面已有的滚动位置）。
    ///
    /// 已经安装过 `.scrollPosition(…)` 的滚动容器（如 `ComicGridContent` 的返回恢复）用这个重载，
    /// 避免对同一滚动容器装两份位置绑定。
    func scrollToTopButton(position: Binding<ScrollPosition>) -> some View {
        modifier(ScrollToTopButtonModifier(position: position))
    }
}

/// 返回顶部按钮修饰器：只负责位置绑定、可见性与按钮形态，不持业务状态、不发起请求。
///
/// 形态与旧项目（`jm_v1` 的 `View+ScrollToTopButton`）对齐：48pt 圆形玻璃按钮＋20pt `arrow.up` 图标
/// ＋柔和投影，右下角 24pt／12pt 边距。显隐走 `scaleEffect`（1 ↔ 0.01，`.smooth(duration: 0.2)`）：显示
/// 时从按钮自身中心放大，隐藏时缩回中心、动画结束后才移出视图树，因此隐藏期间不参与渲染，也不留在
/// 无障碍树里。不用透明度渐变。与旧项目的差异：阈值取半屏（旧项目为一屏，按当前要求调整）。
///
/// 缩放用 `scaleEffect` 而不是 `.transition(.scale)`：过渡的锚点取「`if` 条件容器」的 frame，边距
/// （`padding`）会让它变成「按钮＋边距」的中心，缩放眼看上去会偏移；`scaleEffect` 的锚点始终是
/// 按钮自身的 bounds，与外层边距无关。
private struct ScrollToTopButtonModifier: ViewModifier {
    /// 页面已有的滚动位置；为 `nil` 时由本修饰器自己持有一个。
    let position: Binding<ScrollPosition>?

    @State private var ownedPosition = ScrollPosition()
    /// 按钮的缩放目标：滚过半屏为 `true`。
    @State private var isVisible = false
    /// 按钮是否留在视图树里；隐藏时等缩放动画结束后才置回 `false`。
    @State private var isMounted = false

    private var scrollPosition: Binding<ScrollPosition> {
        position ?? $ownedPosition
    }

    func body(content: Content) -> some View {
        contentWithPosition(content)
            // 只观察滚动几何：超过半屏才显示，避免首屏就压住内容。
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top > geometry.containerSize.height / 2
            } action: { _, isScrolledPastHalfScreen in
                updateVisibility(isScrolledPastHalfScreen)
            }
            .overlay(alignment: .bottomTrailing) {
                if isMounted {
                    button
                        .padding(.trailing, 24)
                        .padding(.bottom, 12)
                }
            }
    }

    /// 显示：先挂载（首帧按 0.01 缩放出现），再由 `onAppear` 放大到 1；隐藏：先缩回 0.01，
    /// `withAnimation` 的完成回调里才移出视图树，隐藏动画不会被移除截断。
    ///
    /// 缩放只由 `withAnimation` 驱动，不再叠加隐式 `.animation`：显隐与 completion 属于同一份
    /// 事务，动画时长和卸载时机可确定。`isMounted && !isVisible` 是动画被中断后的残留态，
    /// 这里直接卸载，避免留下一个缩放到 0.01 的按钮继续占无障碍树。
    private func updateVisibility(_ shouldShow: Bool) {
        if shouldShow {
            if !isMounted {
                // 新挂载：由 `onAppear` 从 0.01 放大，入场动画才完整。
                isMounted = true
            } else if !isVisible {
                // 上一次隐藏动画还没跑完就又滚过半屏：原地放大回来，不重新挂载。
                withAnimation(.smooth(duration: 0.2)) {
                    isVisible = true
                }
            }
            return
        }

        guard isVisible else {
            if isMounted {
                isMounted = false
            }
            return
        }

        withAnimation(.smooth(duration: 0.2)) {
            isVisible = false
        } completion: {
            // 动画期间若又滚过半屏，`isVisible` 已回到 `true`，这里就不卸载。
            if !isVisible {
                isMounted = false
            }
        }
    }

    /// 自带位置时给滚动容器装绑定；复用页面位置时不重复安装。
    @ContentBuilder
    private func contentWithPosition(_ content: Content) -> some View {
        if position == nil {
            content.scrollPosition($ownedPosition)
        } else {
            content
        }
    }

    private var button: some View {
        Button {
            // 与系统「点按已选 Tab 回到顶部」同节奏：旧项目用 UIView.animate(0.25, curveEaseOut)。
            withAnimation(.easeOut(duration: 0.25)) {
                scrollPosition.wrappedValue.scrollTo(edge: .top)
            }
        } label: {
            Image(systemName: "arrow.up")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color.textPrimary)
                .frame(width: 48, height: 48)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        .scaleEffect(isVisible ? 1 : 0.01)
        .accessibilityLabel("返回顶部")
        .onAppear {
            // 挂载后再进入可见态：入场同样走完整的「0.01 → 1」缩放动画。
            withAnimation(.smooth(duration: 0.2)) {
                isVisible = true
            }
        }
    }
}

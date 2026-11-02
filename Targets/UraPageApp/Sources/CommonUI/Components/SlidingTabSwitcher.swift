import SwiftUI

/// 工具栏位置的标签切换组件：胶囊玻璃背景 + 跟随选择滑动的指示块。
///
/// 与分页滑动组件是两个独立组件，可联动也可拆开：
/// - 独立使用：`selectionProgress` 传 `nil`，指示块按 `selection` 取整定位；
/// - 与分页联动：把分页组件的连续进度传进来，指示块随滑动连续位移。
/// 选中变化由调用方决定是否加动画（`withAnimation(.snappy(duration: 0.24))` 与旧项目一致）。
///
/// 尺寸取自旧项目书架页的标签组（只参考 UI，不沿用其私有实现）：字体 15pt medium
/// （`.subheadline` 随动态字号缩放）、文字左右各 10pt、标签最小 44×38、标签之间无间距、
/// 外围内缩 3pt、控件高 44pt。背景自带 `glassEffect`，因此使用它的 `ToolbarItem` 需要
/// 配合 `.sharedBackgroundVisibility(.hidden)` 隐藏工具栏自带的背景，避免叠成两层。
struct SlidingTabSwitcher<Value: Hashable & Identifiable>: View {
    /// 依次展示的标签。
    let tabs: [Value]

    /// 标签文案。
    let title: (Value) -> String

    /// 当前选中项。
    let selection: Value

    /// 分页组件给出的连续进度（`0 ... count - 1`）；独立使用时传 `nil`。
    let selectionProgress: CGFloat?

    /// 点击标签。
    let onSelect: (Value) -> Void

    /// 标签之间没有间距（与旧项目一致）。
    private let itemSpacing: CGFloat = 0

    /// 文字左右内边距（与旧项目一致）。
    private let itemHorizontalPadding: CGFloat = 10

    /// 指示块与控件边缘的内缩（与旧项目一致）。
    private let backgroundInset: CGFloat = 3

    /// 标签最小尺寸（与旧项目一致：最小宽度 44、高度为控件高减去上下内缩）。
    private let minimumItemWidth: CGFloat = 44
    private let minimumItemHeight: CGFloat = 38

    /// 控件高度（与旧项目一致：至少 44，文字变大时随内容长高）。
    private let minimumControlHeight: CGFloat = 44

    @State private var measuredWidths: [Value: CGFloat] = [:]
    @State private var measuredItemHeight: CGFloat = 0

    var body: some View {
        ZStack(alignment: .leading) {
            indicator

            HStack(spacing: itemSpacing) {
                ForEach(tabs) { tab in
                    item(for: tab)
                }
            }
        }
        .padding(backgroundInset)
        .frame(minHeight: minimumControlHeight)
        .glassEffect(.regular.interactive(), in: .capsule)
        .fixedSize(horizontal: true, vertical: false)
    }

    /// 滑动指示块：尺寸与位移都按已测量的标签宽度插值。
    private var indicator: some View {
        Capsule()
            .fill(Color.primary.opacity(0.10))
            .frame(width: indicatorWidth, height: indicatorHeight)
            .offset(x: indicatorOffsetX)
    }

    private func item(for tab: Value) -> some View {
        Button {
            onSelect(tab)
        } label: {
            Text(title(tab))
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
                .foregroundStyle(Color.textPrimary)
                .padding(.horizontal, itemHorizontalPadding)
                .frame(minWidth: minimumItemWidth, minHeight: minimumItemHeight)
                .contentShape(.capsule)
                .onGeometryChange(for: CGSize.self) { $0.size } action: { newSize in
                    measuredWidths[tab] = newSize.width
                    measuredItemHeight = newSize.height
                }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(tab == selection ? .isSelected : [])
    }

    // MARK: - 指示块几何

    /// 当前进度：优先用分页给出的连续值，独立使用时按选中项取整。
    private var progress: CGFloat {
        if let selectionProgress {
            return selectionProgress
        }

        return CGFloat(tabs.firstIndex(of: selection) ?? 0)
    }

    private var indicatorWidth: CGFloat {
        interpolate { width(for: $0) }
    }

    private var indicatorOffsetX: CGFloat {
        interpolate { tab in
            guard let index = tabs.firstIndex(of: tab) else {
                return 0
            }

            return tabs
                .prefix(index)
                .reduce(0) { partialResult, previousTab in
                    partialResult + width(for: previousTab) + itemSpacing
                }
        }
    }

    private var indicatorHeight: CGFloat {
        measuredItemHeight > 0 ? measuredItemHeight : minimumItemHeight
    }

    private func width(for tab: Value) -> CGFloat {
        measuredWidths[tab] ?? estimatedWidth(for: tab)
    }

    /// 首帧（尚未测量）时的估算宽度：按字数估算后再取最小宽度。
    private func estimatedWidth(for tab: Value) -> CGFloat {
        let approximateCharacterWidth: CGFloat = 15
        let estimated = CGFloat(title(tab).count) * approximateCharacterWidth + itemHorizontalPadding * 2
        return max(estimated, minimumItemWidth)
    }

    /// 在相邻两个标签之间按进度插值。
    private func interpolate(_ value: (Value) -> CGFloat) -> CGFloat {
        guard tabs.count > 1 else {
            return tabs.first.map(value) ?? 0
        }

        let maxProgress = CGFloat(tabs.count - 1)
        let clampedProgress = min(max(progress, 0), maxProgress)
        let lowerIndex = min(max(Int(clampedProgress.rounded(.down)), 0), tabs.count - 1)
        let upperIndex = min(lowerIndex + 1, tabs.count - 1)
        let fraction = clampedProgress - CGFloat(lowerIndex)

        let lowerValue = value(tabs[lowerIndex])
        let upperValue = value(tabs[upperIndex])
        return lowerValue + (upperValue - lowerValue) * fraction
    }
}

import SwiftUI

/// 通用设置「下载」分区：两个并发上限滑块。
///
/// 版式与「缓存」分区的磁盘上限一致：标题＋当前值、1 步进的滑块、两端刻度；
/// 说明文字放在标题下方（与「阅读历史」分区一致），拖动中只显示本地值，松手才写回 owner。
struct GeneralDownloadSection: View {
    @Environment(\.downloadSettings) private var downloadSettings

    /// 拖拽中的作品数；松手前不落库。
    @State private var editingWorkLimit: Double?

    /// 拖拽中的页并发；松手前不落库。
    @State private var editingPageConcurrency: Double?

    var body: some View {
        Section {
            DownloadConcurrencyRow(
                title: "同时下载的作品数",
                detail: "每个来源单独计算，多出的作品排队",
                unit: "部",
                value: workLimitValue,
                range: workLimitSliderRange,
            ) { value in
                downloadSettings.selectWorkLimitPerSource(Int(value))
                editingWorkLimit = nil
            }

            DownloadConcurrencyRow(
                title: "单作品并发页数",
                detail: "只影响单个作品的下载速度，调高更占内存",
                unit: "页",
                value: pageConcurrencyValue,
                range: pageConcurrencySliderRange,
            ) { value in
                downloadSettings.selectPageConcurrencyPerWork(Int(value))
                editingPageConcurrency = nil
            }
        } header: {
            Text("下载")
        } footer: {
            Text("全部作品合计最多同时处理 \(AppConfiguration.Downloads.maximumInFlightPageTasks) 页，其余排队。")
        }
    }

    /// 滑块值：拖拽中用本地值，静止时读 owner（页面不直接读写持久化）。
    private var workLimitValue: Binding<Double> {
        Binding(
            get: { editingWorkLimit ?? Double(downloadSettings.workLimitPerSource) },
            set: { editingWorkLimit = $0 },
        )
    }

    private var pageConcurrencyValue: Binding<Double> {
        Binding(
            get: { editingPageConcurrency ?? Double(downloadSettings.pageConcurrencyPerWork) },
            set: { editingPageConcurrency = $0 },
        )
    }

    /// 滑块只能取整数档位，范围来自唯一归属处。
    private var workLimitSliderRange: ClosedRange<Double> {
        let range = AppConfiguration.Downloads.workLimitPerSourceRange
        return Double(range.lowerBound) ... Double(range.upperBound)
    }

    private var pageConcurrencySliderRange: ClosedRange<Double> {
        let range = AppConfiguration.Downloads.pageConcurrencyPerWorkRange
        return Double(range.lowerBound) ... Double(range.upperBound)
    }
}

/// 单个并发上限滑块行：标题、说明、当前值与两端刻度，松手才回调写回。
///
/// 拖动中的值由调用方的 `Binding` 承接，行内不持有状态；
/// 调用方负责在 `onCommit` 里落库并清掉本地拖拽值。
private struct DownloadConcurrencyRow: View {
    let title: String
    let detail: String
    let unit: String
    let value: Binding<Double>
    let range: ClosedRange<Double>
    let onCommit: @MainActor (Double) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)

                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                }

                Spacer(minLength: 16)

                // 读绑定值：拖拽中显示本地值，静止时显示 owner 值。
                Text("\(Int(value.wrappedValue)) \(unit)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.textSecondary)
            }

            Slider(
                value: value,
                in: range,
                step: 1,
            ) {
                Text(title)
            } minimumValueLabel: {
                scaleLabel(range.lowerBound)
            } maximumValueLabel: {
                scaleLabel(range.upperBound)
            } onEditingChanged: { isEditing in
                guard !isEditing else { return }

                onCommit(value.wrappedValue)
            }
            .tint(Color.brandPrimary)
        }
    }

    /// 两端刻度：与磁盘上限的「1G／10G」同款小号次要色。
    private func scaleLabel(_ value: Double) -> some View {
        Text("\(Int(value))")
            .font(.caption)
            .foregroundStyle(Color.textSecondary)
    }
}

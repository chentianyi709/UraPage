import SwiftUI

/// 通用设置「阅读历史」分区：保留时间档位。
struct GeneralReadingHistorySection: View {
    @Environment(\.readingHistorySettings) private var readingHistorySettings

    var body: some View {
        Section {
            // 保留时间：标题 + 当前档位，下面一条 30 天～不限制 的滑块（与旧项目同形）。
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("阅读历史保留时间")

                        Text("低于当前周期时会立即清理过期历史")
                            .font(.caption)
                            .foregroundStyle(Color.textSecondary)
                    }

                    Spacer(minLength: 16)

                    Text(readingHistorySettings.retention.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.textSecondary)
                }

                Slider(
                    value: retentionSliderBinding,
                    in: 0 ... Double(max(ReadingHistoryRetention.allCases.count - 1, 0)),
                    step: 1,
                ) {
                    Text("阅读历史保留时间")
                } minimumValueLabel: {
                    Text(ReadingHistoryRetention.allCases.first?.title ?? "")
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                } maximumValueLabel: {
                    Text(ReadingHistoryRetention.allCases.last?.title ?? "")
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                }
                .tint(Color.brandPrimary)
            }
        } header: {
            Text("阅读历史")
        }
    }

    /// 滑块按档位下标取值；拖动即写回 owner（缩短时长时 owner 会立即清理过期历史）。
    private var retentionSliderBinding: Binding<Double> {
        Binding(
            get: {
                Double(ReadingHistoryRetention.allCases.firstIndex(of: readingHistorySettings.retention) ?? 0)
            },
            set: { newValue in
                let index = Int(newValue.rounded())
                guard ReadingHistoryRetention.allCases.indices.contains(index) else { return }

                readingHistorySettings.select(ReadingHistoryRetention.allCases[index])
            },
        )
    }
}

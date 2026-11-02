import SwiftUI

/// 通用设置「缓存」分区：图片磁盘缓存上限。
struct GeneralCacheLimitSection: View {
    @Environment(\.imageCacheSettings) private var imageCacheSettings

    /// 滑块拖拽中的本地上限（GB）；松手时才写回 owner，避免拖动过程反复落库。
    @State private var editingLimitGB: Double?

    var body: some View {
        Section {
            cacheLimitControl
        } header: {
            Text("缓存")
        }
    }

    /// 磁盘缓存上限：标题＋说明＋当前档位，下面一条 1–10 GB 滑块（松手写回）。
    private var cacheLimitControl: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("图片磁盘缓存上限")

                    Text("只限制浏览时缓存的图片，不影响已下载的作品")
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                }

                Spacer(minLength: 16)

                // 读绑定值：拖拽中显示本地值，静止时显示 owner 值。
                Text("\(Int(diskSizeLimitGBBinding.wrappedValue)) GB")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.textSecondary)
            }

            Slider(
                value: diskSizeLimitGBBinding,
                in: Double(minimumDiskSizeLimitGB) ... Double(maximumDiskSizeLimitGB),
                step: 1,
            ) {
                Text("图片磁盘缓存上限")
            } minimumValueLabel: {
                Text("\(minimumDiskSizeLimitGB)G")
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
            } maximumValueLabel: {
                Text("\(maximumDiskSizeLimitGB)G")
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
            } onEditingChanged: { isEditing in
                guard !isEditing, let editingLimitGB else {
                    return
                }

                // 松手写回，然后清掉本地拖拽值，显示回到 owner 的权威值。
                imageCacheSettings
                    .selectDiskSizeLimit(bytes: Int(editingLimitGB) * ByteSizeFormatting.bytesPerGB)
                self.editingLimitGB = nil
            }
            .tint(Color.brandPrimary)
        }
    }

    /// 滑块值：拖拽中用本地值，静止时读 owner（页面不直接读写持久化）。
    private var diskSizeLimitGBBinding: Binding<Double> {
        Binding(
            get: {
                editingLimitGB ??
                    Double(imageCacheSettings.diskSizeLimitBytes / ByteSizeFormatting.bytesPerGB)
            },
            set: { editingLimitGB = $0 },
        )
    }

    private var minimumDiskSizeLimitGB: Int {
        BrowsingImageConfiguration.minimumDiskSizeLimit / ByteSizeFormatting.bytesPerGB
    }

    private var maximumDiskSizeLimitGB: Int {
        BrowsingImageConfiguration.maximumDiskSizeLimit / ByteSizeFormatting.bytesPerGB
    }
}

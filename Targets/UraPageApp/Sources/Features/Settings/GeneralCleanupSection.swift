import SwiftUI

/// 通用设置「清理」分区：四个清理入口及其二次确认。
///
/// 所有清理入口集中在这里：图片缓存（可重新下载）→ 清除下载记录 → 全部阅读记录（正常数据）→
/// 清理其他数据（固定最后）。动作与文案由 `GeneralCleanupModel` 承担。
struct GeneralCleanupSection: View {
    @Environment(\.imageCacheSettings) private var imageCacheSettings
    @Environment(\.readingHistorySettings) private var readingHistorySettings
    @Environment(\.readingHistoryStore) private var readingHistoryStore
    @Environment(\.downloadManager) private var downloadManager

    @State private var model: GeneralCleanupModel?
    @State private var showsClearCacheConfirmation = false
    @State private var showsClearReadingHistoryConfirmation = false
    @State private var showsClearDownloadsConfirmation = false

    var body: some View {
        Section {
            CleanupActionRow(
                title: model?.isClearingCache == true ? "正在清除图片缓存..." : "清除图片缓存",
                detail: "清除只影响已缓存的图片，浏览时会按需重新下载。",
                status: cacheStatus,
                isDisabled: model?.isClearingCache == true,
            ) {
                showsClearCacheConfirmation = true
            }

            CleanupActionRow(
                title: model?.isClearingDownloads == true ? "正在清除下载记录..." : "清除下载记录",
                detail: "会删除全部下载记录及已下载的本地图片，正在下载的任务会一并停止。",
                status: downloadsStatus,
                isDisabled: model?.isClearingData == true,
            ) {
                showsClearDownloadsConfirmation = true
            }

            CleanupActionRow(
                title: model?.isClearingReadingHistory == true ? "正在清除阅读记录..." : "清除全部阅读记录",
                detail: "会同时清除各作品已保存的继续阅读进度。",
                isDisabled: model?.isClearingData == true,
            ) {
                showsClearReadingHistoryConfirmation = true
            }

            CleanupActionRow(
                title: model?.otherDataActionTitle ?? "清理其他数据",
                detail: "清理无法读取的下载记录、阅读记录、无记录的孤立下载资产，以及导出中断残留的临时压缩包；正常数据不会被删除。",
                status: otherDataStatus,
                isDisabled: model?.otherDataDisabled ?? true,
            ) {
                Task { await model?.handleOtherDataTap() }
            }
        } header: {
            Text("清理")
        }
        .alert("清除图片缓存？", isPresented: $showsClearCacheConfirmation) {
            Button("取消", role: .cancel) {}
            Button("清除", role: .destructive) {
                Task { await model?.clearCache() }
            }
        } message: {
            Text("将清空 App 的图片磁盘缓存，浏览时会按需重新下载。")
        }
        .alert("清除全部阅读记录？", isPresented: $showsClearReadingHistoryConfirmation) {
            Button("取消", role: .cancel) {}
            Button("清除", role: .destructive) {
                Task { await model?.clearReadingHistory() }
            }
        } message: {
            Text("将清除全部阅读历史，以及各作品已保存的继续阅读进度。")
        }
        .alert("清除下载记录？", isPresented: $showsClearDownloadsConfirmation) {
            Button("取消", role: .cancel) {}
            Button("清除", role: .destructive) {
                Task { await model?.clearDownloads() }
            }
        } message: {
            Text("将删除全部下载记录和已下载的本地图片，正在下载的任务会一并停止。")
        }
        .alert("清理其他数据？", isPresented: cleanupConfirmationBinding) {
            Button("取消", role: .cancel) {}
            Button("清理", role: .destructive) {
                Task { await model?.cleanOtherData() }
            }
        } message: {
            Text(model?.otherDataCleanupMessage ?? "")
        }
        .task {
            if model == nil {
                model = GeneralCleanupModel(
                    imageCacheSettings: imageCacheSettings,
                    readingHistorySettings: readingHistorySettings,
                    downloadManager: downloadManager,
                    readingHistoryStore: readingHistoryStore,
                )
            }
            await model?.prepare()
        }
    }

    /// 「清理其他数据」的确认状态由 model 持有（检查完成后才置位）。
    private var cleanupConfirmationBinding: Binding<Bool> {
        Binding(
            get: { model?.showsCleanupConfirmation ?? false },
            set: { model?.showsCleanupConfirmation = $0 },
        )
    }

    /// 图片缓存占用：大小／加载图标／失败图标。
    private var cacheStatus: CleanupRowStatus? {
        guard let model else { return nil }

        return status(for: model.cacheUsageState)
    }

    /// 下载资产占用：大小／加载图标／失败图标。
    private var downloadsStatus: CleanupRowStatus? {
        guard let model else { return nil }

        return status(for: model.downloadsUsageState)
    }

    /// 「清理其他数据」：待检查／检查中／检查失败／无或项数。
    private var otherDataStatus: CleanupRowStatus? {
        guard let model else { return nil }

        switch model.otherDataStatus {
        case .idle:
            return .text("点击检查")

        case .scanning:
            return .loading(accessibilityLabel: "正在检查")

        case .failed:
            return .failed(accessibilityLabel: "检查失败")

        case let .count(total):
            return .text(total == 0 ? "无" : "\(total) 项")
        }
    }

    /// 把占用状态映射为右侧展示；大小文案统一走 `ByteSizeFormatting`。
    private func status(for usage: StorageUsageState) -> CleanupRowStatus {
        switch usage {
        case .loading:
            return .loading(accessibilityLabel: "正在计算占用")

        case .failed:
            return .failed(accessibilityLabel: "占用读取失败")

        case let .available(bytes):
            return .text(ByteSizeFormatting.formatted(bytes))
        }
    }
}

/// 清理入口右侧的状态显示。
private enum CleanupRowStatus {
    /// 文本：占用大小、待清理项数或「点击检查」。
    case text(String)

    /// 正在读取或检查：显示加载图标。
    case loading(accessibilityLabel: String)

    /// 读取或检查失败：显示失败图标。
    case failed(accessibilityLabel: String)
}

/// 清理分区的一行：破坏性按钮 + 右侧状态 + 下方说明。
private struct CleanupActionRow: View {
    let title: String
    let detail: String
    var status: CleanupRowStatus?
    var isDisabled = false
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button(role: .destructive, action: action) {
                HStack(spacing: 12) {
                    Text(title)

                    Spacer()

                    if let status {
                        statusView(status)
                    }
                }
            }
            .disabled(isDisabled)

            Text(detail)
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
        }
    }

    /// 右侧状态：文本按副标题样式，加载与失败只给图标并补无障碍说明。
    @ViewBuilder
    private func statusView(_ status: CleanupRowStatus) -> some View {
        switch status {
        case let .text(value):
            Text(value)
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)

        case let .loading(accessibilityLabel):
            ProgressView()
                .controlSize(.small)
                .accessibilityLabel(accessibilityLabel)

        case let .failed(accessibilityLabel):
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)
                .accessibilityLabel(accessibilityLabel)
        }
    }
}

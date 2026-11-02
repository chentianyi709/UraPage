import SwiftUI

/// 作品封面上的导出进度蒙版：与下载覆盖层同一套蒙版与圆环，中央显示导出百分比。
///
/// 只有正在导出的作品显示；导出不提供取消入口，进度由 `DownloadsExportModel` 推送。
/// 只负责展示，点击穿透到封面按钮。
struct ExportCoverOverlay: View {
    /// 已完成的整数百分比；`nil` 表示还没拿到总页数。
    let percent: Int?

    var body: some View {
        ZStack {
            Color.black.opacity(0.42)
            ring
        }
        .clipShape(
            RoundedRectangle(
                cornerRadius: ComicGridMetrics.coverCornerRadius,
                style: .continuous,
            ),
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("导出中")
        .accessibilityValue(percent.map { "\($0)%" } ?? "准备中")
    }

    /// 有百分比时显示百分比，准备阶段显示活动指示。
    private var ring: some View {
        CoverProgressRing(progress: percent.map { Double($0) / 100 }) {
            VStack(spacing: 2) {
                if let percent {
                    Text("\(percent)%")
                        .font(.system(size: 16, weight: .bold))
                        .monospacedDigit()
                } else {
                    ProgressView()
                        .tint(.white)
                }

                Text("导出中")
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(Color.white)
        }
    }
}

/// 单张封面上的导出进度入口：自己订阅导出状态与进度。
///
/// 不在网格层读取进度，百分比每变一档只重算这一层叠层，不牵动整个网格的 `items.map`、
/// 卡片菜单与懒加载布局。
struct ExportProgressBadge: View {
    let model: DownloadsExportModel
    let identity: ComicIdentity

    var body: some View {
        if model.exportingIdentity == identity {
            ExportCoverOverlay(percent: model.progress)
        }
    }
}

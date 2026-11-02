import SwiftUI

/// 封面进度圆环：可选比例加中央内容，由下载与导出两个覆盖层共用，保证同一视觉。
struct CoverProgressRing<Center: View>: View {
    /// 已完成比例；为 `nil` 时只画底环，中央自行显示活动指示。
    let progress: Double?

    private let center: Center

    init(progress: Double?, @ContentBuilder center: () -> Center) {
        self.progress = progress
        self.center = center()
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.26), lineWidth: 6)

            if let progress {
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(Color.brandPrimary, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }

            center
        }
        .frame(width: 72, height: 72)
        .accessibilityHidden(true)
    }
}

/// 作品封面上的下载覆盖层：未完成时盖一层蒙版，中央显示进度或状态。
///
/// 单章作品显示当前章节的单位百分比；多章作品显示「已完成章节/总章节」＋当前章节百分比；
/// 阶段未到百分比时显示「准备中」（打开章节）或「检查中」（核对已下载内容），只剩封面时显示「封面下载中」；
/// 暂停／失败显示对应操作图标。只负责展示，点击穿透到封面按钮。
struct DownloadCoverOverlay: View {
    let summary: DownloadedComicSummary

    var body: some View {
        if summary.state == .completed {
            EmptyView()
        } else {
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
        }
    }

    /// 进度环只在有具体比例时显示；准备／检查阶段只显示状态文案。
    private var clampedProgress: Double? {
        guard case let .some(.units(progress)) = summary.progress else { return nil }

        return min(max(progress, 0), 1)
    }

    private var ring: some View {
        CoverProgressRing(progress: clampedProgress) {
            center
        }
    }

    @ContentBuilder
    private var center: some View {
        switch summary.state {
        case .queued:
            Text("等待中")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.white)

        case .downloading:
            downloadingCenter

        case .paused:
            Image(systemName: "play.fill")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(Color.white)

        case .failed:
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(Color.white)

        case .completed:
            EmptyView()
        }
    }

    /// 单章显示当前章节百分比；多章显示章节数与当前章节进度或阶段。
    @ContentBuilder
    private var downloadingCenter: some View {
        if summary.chapterCount > 1 {
            VStack(spacing: 2) {
                Text("\(summary.completedChapterCount)/\(summary.chapterCount)")
                    .font(.system(size: 16, weight: .bold))
                    .monospacedDigit()

                progressOrStageText
                    .font(.system(size: 11, weight: .semibold))
                    .monospacedDigit()
            }
            .foregroundStyle(Color.white)
        } else {
            switch summary.progress {
            case let .some(.units(progress)):
                Text(percentText(progress))
                    .font(.system(size: 18, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(Color.white)

            case .some(.preparing):
                activityLabel("准备中")

            case .some(.checking):
                activityLabel("检查中")

            case .none:
                activityLabel("封面下载中")
            }
        }
    }

    /// 多章副标题：有比例就显示百分比，否则显示当前阶段；只剩封面时提示封面处理中。
    private var progressOrStageText: Text {
        switch summary.progress {
        case let .some(.units(progress)):
            Text(percentText(progress))

        case .some(.preparing):
            Text("准备中")

        case .some(.checking):
            Text("检查中")

        case .none:
            Text("封面下载中")
        }
    }

    private func percentText(_ progress: Double) -> String {
        "\(Int((min(max(progress, 0), 1) * 100).rounded()))%"
    }

    private func activityLabel(_ title: String) -> some View {
        VStack(spacing: 4) {
            ProgressView()
                .tint(.white)
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.white)
        }
    }
}

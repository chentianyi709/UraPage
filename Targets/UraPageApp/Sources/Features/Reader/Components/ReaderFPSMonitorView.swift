// 仅供开发期间观察 Reader 帧节奏；Release 构建不会编译或运行该组件。
#if DEBUG
    import SwiftUI
    import UIKit

    /// 在 Reader 右上角显示主线程 DisplayLink 帧率，用于定位滚动掉帧。
    struct ReaderFPSMonitorView: View {
        var body: some View {
            ReaderFPSMonitorRepresentable()
                .frame(width: 92, height: 58)
                .padding(.top, 54)
                .padding(.trailing, 12)
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity,
                    alignment: .topTrailing,
                )
                .allowsHitTesting(false)
                .zIndex(10)
        }
    }

    /// 把 UIKit DisplayLink 监视标签嵌入 SwiftUI Reader。
    private struct ReaderFPSMonitorRepresentable: UIViewRepresentable {
        /// 创建并启动帧率监视标签。
        func makeUIView(context _: Context) -> ReaderFPSMonitorLabel {
            ReaderFPSMonitorLabel()
        }

        /// 监视器不依赖 SwiftUI 状态，无需在更新周期重新配置。
        func updateUIView(_: ReaderFPSMonitorLabel, context _: Context) {}

        /// Reader 离开时停止 DisplayLink，避免后台继续采样。
        static func dismantleUIView(
            _ uiView: ReaderFPSMonitorLabel,
            coordinator _: (),
        ) {
            uiView.stopMonitoring()
        }
    }

    /// 统计最近半秒 DisplayLink 平均帧率、最大间隔和疑似漏帧数。
    private final class ReaderFPSMonitorLabel: UILabel {
        private let contentInsets = UIEdgeInsets(
            top: 4,
            left: 8,
            bottom: 4,
            right: 8,
        )
        private var displayLink: CADisplayLink?
        private var frameCount = 0
        private var lastUpdateTime: CFTimeInterval = 0
        private var previousFrameTime: CFTimeInterval = 0
        private var previousTargetTime: CFTimeInterval = 0
        private var previousScheduledInterval: CFTimeInterval = 0
        private var maximumFrameInterval: CFTimeInterval = 0
        private var droppedFrameCount = 0

        override init(frame: CGRect) {
            super.init(frame: frame)
            setupAppearance()
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        deinit {
            displayLink?.invalidate()
        }

        /// 进入窗口后开始采样，离开窗口立即停止。
        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window == nil {
                stopMonitoring()
            } else {
                startMonitoringIfNeeded()
            }
        }

        /// 在标签内侧留出固定文字边距。
        override func drawText(in rect: CGRect) {
            super.drawText(in: rect.inset(by: contentInsets))
        }

        /// 停止帧率采样并重置本次统计。
        func stopMonitoring() {
            displayLink?.invalidate()
            displayLink = nil
            frameCount = 0
            lastUpdateTime = 0
            previousFrameTime = 0
            previousTargetTime = 0
            previousScheduledInterval = 0
            maximumFrameInterval = 0
            droppedFrameCount = 0
        }

        /// 配置不影响 Reader 交互的紧凑调试样式。
        private func setupAppearance() {
            font = .monospacedDigitSystemFont(
                ofSize: 11,
                weight: .semibold,
            )
            numberOfLines = 3
            text = "DL -- FPS\nMAX -- ms\nDROP --"
            textColor = .systemGreen
            textAlignment = .center
            backgroundColor = UIColor.black.withAlphaComponent(0.72)
            isUserInteractionEnabled = false

            layer.cornerRadius = 9
            layer.cornerCurve = .continuous
            layer.borderColor = UIColor.white.withAlphaComponent(0.18).cgColor
            layer.borderWidth = 0.5
            clipsToBounds = true
        }

        /// 按当前屏幕上限创建最高 120Hz 的 DisplayLink。
        private func startMonitoringIfNeeded() {
            guard displayLink == nil else {
                return
            }

            let link = CADisplayLink(
                target: self,
                selector: #selector(handleDisplayLink(_:)),
            )
            let maximumFPS = window?.windowScene?.screen.maximumFramesPerSecond
                ?? 120
            let preferredFPS = min(maximumFPS, 120)
            link.preferredFrameRateRange = CAFrameRateRange(
                minimum: Float(min(preferredFPS, 60)),
                maximum: Float(preferredFPS),
                preferred: Float(preferredFPS),
            )
            link.add(to: .main, forMode: .common)
            displayLink = link
        }

        /// 每半秒更新平均帧率、最大帧间隔和疑似漏帧数。
        @objc private func handleDisplayLink(_ displayLink: CADisplayLink) {
            let now = displayLink.timestamp
            let scheduledInterval = max(
                displayLink.targetTimestamp - now,
                1.0 / 120.0,
            )
            guard previousFrameTime > 0 else {
                previousFrameTime = now
                previousTargetTime = displayLink.targetTimestamp
                previousScheduledInterval = scheduledInterval
                lastUpdateTime = now
                return
            }

            let frameInterval = now - previousFrameTime
            previousFrameTime = now
            if previousTargetTime > 0,
               previousScheduledInterval > 0 {
                // 只有当前帧晚于上一帧预告的目标时间才计数，避免把 ProMotion 主动降频当成掉帧。
                let lateness = now - previousTargetTime
                if lateness >= previousScheduledInterval * 0.5 {
                    droppedFrameCount += max(
                        Int((lateness / previousScheduledInterval).rounded()),
                        1,
                    )
                }
            }
            previousTargetTime = displayLink.targetTimestamp
            previousScheduledInterval = scheduledInterval
            frameCount += 1
            maximumFrameInterval = max(
                maximumFrameInterval,
                frameInterval,
            )

            let elapsed = now - lastUpdateTime
            guard elapsed >= 0.5 else {
                return
            }

            let fps = Double(frameCount) / elapsed
            text = String(
                format: "DL %.0f FPS\nMAX %.1f ms\nDROP %d",
                fps,
                maximumFrameInterval * 1000,
                droppedFrameCount,
            )
            frameCount = 0
            lastUpdateTime = now
            maximumFrameInterval = 0
            droppedFrameCount = 0
        }
    }
#endif

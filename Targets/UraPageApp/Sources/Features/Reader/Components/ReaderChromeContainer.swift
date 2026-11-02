import SwiftUI

/// 集中定义系统 Toolbar 与页码控制器共用的动画节奏。
enum ReaderChromeAnimation {
    static let duration = 0.24

    /// 使用接近系统 Toolbar 的快速弹性曲线。
    static var value: Animation {
        .snappy(duration: duration)
    }
}

/// 向来源 Reader 内容提供当前控制器的轻量展示状态和操作。
struct ReaderChromeConfiguration {
    let isVisible: Bool
    let tapCount: Int
    let onToggle: () -> Void
    let onScrollStart: () -> Void
}

/// 统一管理 Reader 标题栏、设置、主题、返回手势和控制器显隐。
///
/// 容器不读取来源 ViewModel 或当前页；高频页码观察仍由来源页面的独立子视图承担。
struct ReaderChromeContainer<Content: View>: View {
    @Environment(\.colorScheme) private var inheritedColorScheme
    @Environment(\.readerSettings) private var settings

    @State private var areControlsVisible = false
    @State private var isPresentingSettings = false

    private let title: String
    private let isContentReady: Bool
    private let content: (ReaderChromeConfiguration) -> Content

    /// 创建来源无关的 Reader 控制器外壳。
    init(
        title: String,
        isContentReady: Bool,
        @ContentBuilder content: @escaping (ReaderChromeConfiguration) -> Content,
    ) {
        self.title = title
        self.isContentReady = isContentReady
        self.content = content
    }

    var body: some View {
        ZStack {
            // Reader 独立主题只作用于漫画内容和 Canvas。
            // Toolbar 保留外层 NavigationStack 的颜色环境，使系统返回、
            // 标题和设置按钮由同一套系统玻璃样式解析前景色。
            content(configuration)
                .environment(\.colorScheme, colorScheme)
        }
        .ignoresSafeArea()
        .restoresReaderInteractivePopGesture(
            // 加载／失败／空态没有 Canvas 点击入口，必须允许滑动退出。
            isEnabled: !isContentReady
                || !settings.disablesSwipeBackWhenChromeHidden
                || areControlsVisible,
        )
        .toolbar {
            ReaderChromeToolbar(
                title: title,
                onOpenSettings: presentSettings,
            )
        }
        .toolbarVisibility(
            areControlsVisible ? .visible : .hidden,
            for: .navigationBar,
        )
        // 导航栏与 Reader 控制器使用同一主题；系统返回按钮、
        // 自定义标题和设置按钮由 Toolbar 层级统一解析语义色。
        .toolbarColorScheme(colorScheme, for: .navigationBar)
        .sheet(isPresented: $isPresentingSettings) {
            ReaderSettingsSheet()
                .presentationDetents([.medium, .large])
                .presentationBackground(Color.pageBackground)
                // Sheet 是独立 presentation；需要让承载背景和内容
                // 一起跟随 Reader 主题，不能只覆盖内容环境。
                .preferredColorScheme(colorScheme)
        }
    }

    /// 向来源 Reader 内容提供当前控制器状态。
    private var configuration: ReaderChromeConfiguration {
        ReaderChromeConfiguration(
            isVisible: areControlsVisible,
            tapCount: settings.chromeToggleMode.tapCount,
            onToggle: toggleControls,
            onScrollStart: hideControls,
        )
    }

    /// 按当前单击或双击设置，同步显示或隐藏 Reader 控制器。
    private func toggleControls() {
        withAnimation(ReaderChromeAnimation.value) {
            areControlsVisible.toggle()
        }
    }

    /// 开始滚动时隐藏 Reader 控制器；已隐藏时不产生无效动画事务。
    private func hideControls() {
        guard areControlsVisible else {
            return
        }

        withAnimation(ReaderChromeAnimation.value) {
            areControlsVisible = false
        }
    }

    /// 打开当前 Reader 会话的设置 Sheet。
    private func presentSettings() {
        isPresentingSettings = true
    }

    /// 返回 Reader 实际使用的颜色模式；跟随 App 时沿用全局主题结果。
    private var colorScheme: ColorScheme {
        settings.themeMode.colorScheme ?? inheritedColorScheme
    }
}

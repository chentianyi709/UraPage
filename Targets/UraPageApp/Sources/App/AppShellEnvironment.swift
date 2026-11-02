import SwiftUI

/// App Shell 在体验根边界提供给来源页面与组件的能力。
///
/// 三者都由 App Shell 创建、随体验根安装一次：来源页面按需读取，不逐层传参；
/// 它们都有状态与生命周期（导航栈、弹窗、体验资源），因此不用全局单例。
@MainActor
struct AppShellEnvironment {
    private let model: AppShellModel

    /// 页面导航入口（定位当前 Tab 的栈、跨来源详情转换）。
    let navigator: AppNavigator

    /// 跨来源页面展示来源名称时读取已注册的展示信息。
    var sourceDescriptors: [SourceDescriptor] {
        model.descriptors
    }

    init(model: AppShellModel, host: AppSourceHost) {
        self.model = model
        navigator = AppNavigator(model: model, host: host)
    }

    /// 呈现一个 App 级弹窗；route 由调用方给出（含它需要的上下文）。
    ///
    /// 所有 App 级弹窗共用这一个入口：新增弹窗只需在 `AppSheetRoute` 加 case、
    /// 由 `AppShellView` 的 `sheetContent(for:)` 构造内容，这里不再增加方法。
    /// 直接调用生命周期 owner，不在 Environment 中另存动作闭包。
    func presentSheet(_ route: AppSheetRoute) {
        model.presentSheet(route)
    }

    /// 切换到本源 Tab 的根页面（选中 Tab 并清空其栈）；来源页面用本源 typed Tab 包一层调用。
    func selectRoot(of tab: SourceTab) {
        model.selectRoot(of: tab)
    }
}

extension EnvironmentValues {
    /// 当前体验的 App Shell 能力存储槽；写入用 `\.appShellStorage`（写入路径先读缺省，缺省必须可读）。
    @Entry var appShellStorage: AppShellEnvironment?

    /// 读取入口：由 `AppShellView` 安装，未安装即暴露装配错误。
    var appShell: AppShellEnvironment {
        guard let appShellStorage else {
            preconditionFailure("appShell 未安装：来源页面必须位于 AppShellView 的体验根边界内")
        }

        return appShellStorage
    }
}

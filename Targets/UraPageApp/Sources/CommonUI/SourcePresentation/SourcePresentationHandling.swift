import SwiftUI

/// 通用来源控件需要的呈现能力；由 App Shell 实现，CommonUI 不反向引用 App 类型。
/// 来源切换与设置仍由同一个 Shell owner 持有，不在 Environment 中保存动作闭包。
@MainActor
protocol SourcePresentationHandling: AnyObject {
    func presentSourceSelection()
    func presentSourceSettings(for sourceID: ComicSourceID)
}

extension EnvironmentValues {
    /// 来源切换与设置呈现入口存储槽；写入用 `\.sourcePresentationStorage`（写入路径先读缺省，缺省必须可读）。
    @Entry var sourcePresentationStorage: (any SourcePresentationHandling)?

    /// 读取入口：由 App Shell 安装，未安装即暴露装配错误。
    var sourcePresentation: any SourcePresentationHandling {
        guard let sourcePresentationStorage else {
            preconditionFailure("sourcePresentation 未安装：来源控件必须位于 App Shell 内")
        }

        return sourcePresentationStorage
    }
}

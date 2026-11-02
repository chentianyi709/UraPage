import SwiftUI

/// 来源 Logo 的呈现方式。
///
/// 用枚举而不是"可空资源名"，避免出现"没有资源名就表示要自绘"这类隐式约定；
/// 具体的绘制规格由 `SourceLogoView` 统一负责。
enum SourceLogo: Hashable, Sendable {
    /// App Assets 中的图片资源名。
    case asset(String)

    /// 自绘标识：品牌色圆角矩形衬一个汉字（例如绅士的"绅"）。
    case drawn(monogram: String)
}

/// 一个来源在 App 中的展示信息。
struct SourceDescriptor: Hashable, Sendable {
    let sourceID: ComicSourceID
    let displayName: String

    /// 来源 Logo 的呈现方式；由 `SourceLogoView` 统一渲染。
    let logo: SourceLogo
}

extension EnvironmentValues {
    /// 来源展示信息存储槽；写入用 `\.sourceDescriptorStorage`（写入路径先读缺省，缺省必须可读）。
    @Entry var sourceDescriptorStorage: SourceDescriptor?

    /// 读取入口：当前体验的来源展示信息（来源名、Logo 资源名）。
    ///
    /// 由 Module 的公共 root／destination／settingsSheet 边界安装，页面与组件按需读取，
    /// 不再把来源名/Logo 作为参数逐层传递。未安装即暴露装配错误。
    var sourceDescriptor: SourceDescriptor {
        guard let sourceDescriptorStorage else {
            preconditionFailure("sourceDescriptor 未安装：来源页面必须由来源 Module 安装后展示")
        }

        return sourceDescriptorStorage
    }
}

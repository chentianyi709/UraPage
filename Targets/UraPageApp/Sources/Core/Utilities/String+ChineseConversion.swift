import Foundation

extension String {
    /// 使用系统文字转换生成简体中文；无法转换时保留原文。
    ///
    /// 只用于来源内部业务文本识别或明确要求转换的展示值，
    /// 不擅自替换页面最终展示字段。
    func convertedToSimplifiedChinese() -> String {
        applyingTransform(StringTransform("Traditional-Simplified"), reverse: false) ?? self
    }

    /// 使用系统文字转换生成繁体中文；无法转换时保留原文。
    func convertedToTraditionalChinese() -> String {
        applyingTransform(StringTransform("Simplified-Traditional"), reverse: false) ?? self
    }
}

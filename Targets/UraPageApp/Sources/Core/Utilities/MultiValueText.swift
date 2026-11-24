import Foundation

/// 多值展示字段在 SwiftData 行里的唯一存法：U+001F 连接的可检索文本列。
///
/// 数组属性在 SwiftData 里存成二进制、元素级查询不可用（探针见 2026-10-17），
/// 所以作者／标签／分类这类既要展示又要参与 `localizedStandardContains` 检索的字段
/// 统一存文本列，读写经模型的 `authors`／`tags`／`categories` 计算属性还原成数组。
enum MultiValueText {
    /// Unit Separator：不会出现在正常展示文本里，保证拆分无歧义。
    private static let separator = "\u{1F}"

    /// 多值连接为可检索文本列；空数组得到空串。
    static func joined(_ values: [String]) -> String {
        values.joined(separator: separator)
    }

    /// 文本列还原为多值；空串得到空数组，保留空值元素。
    static func values(from text: String) -> [String] {
        text.isEmpty ? [] : text.components(separatedBy: separator)
    }
}

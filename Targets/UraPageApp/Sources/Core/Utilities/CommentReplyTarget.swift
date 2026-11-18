import Foundation

/// 从来源给出的「回复 某某：」「@某某」文本里取出被回复人。
///
/// 回复目标在各来源的形态不同：绅士在 `<em>` 里给一段提及文本，其他来源可能把它拼在正文前缀。
/// 解析（DOM 选择、字段取值）留在各自 mapper，清洗规则统一放在这里——
/// 去掉「回复／回覆／@」前缀与首尾标点，只剩用户名。
///
/// 回复楼主时没有具体对象，清洗结果为空；调用方按 `nil` 处理，界面就不显示「回复 @」。
enum CommentReplyTarget {
    /// 取出被回复人的名字；没有对象或文本只有「回复：」时返回 `nil`。
    static func name(from text: String) -> String? {
        let normalized = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let cleaned = normalized
            .replacingOccurrences(
                of: #"^(?:回复|回覆|@|＠)\s*"#,
                with: "",
                options: .regularExpression,
            )
            .trimmingCharacters(
                in: CharacterSet(charactersIn: " :：@＠")
                    .union(.whitespacesAndNewlines),
            )

        return cleaned.isEmpty ? nil : cleaned
    }
}

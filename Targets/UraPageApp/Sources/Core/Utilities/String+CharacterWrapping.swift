import Foundation

extension String {
    /// 在每个字符之间插入零宽空格（U+200B），让 `Text` 可以逐字换行。
    ///
    /// 中文没有单词边界，`Text` 默认把断点放在“最后一个完整词”之后，一行常填不满
    /// （多行说明文字的行尾留白尤其明显）。插入零宽空格后每个字符之间都是合法断点，
    /// 文字占满整行再换行；零宽空格不可见、不改读音，只影响断行位置。
    ///
    /// 注意：返回值本身带零宽空格，只用于展示文案，不要参与比较、查找或持久化。
    var allowingLineBreakBetweenCharacters: String {
        map { String($0) }.joined(separator: Self.zeroWidthSpace)
    }

    /// 零宽空格（U+200B）：可见宽度为 0，但会被 `Text` 当作合法断点。
    private static let zeroWidthSpace = "\u{200B}"
}

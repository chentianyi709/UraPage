/// 统一生成 Reader 页码组件使用的定宽补零文本。
enum ReaderPageNumberText {
    /// 按总页数的位数补齐当前页，例如第 1 页、共 100 页返回 `001`。
    static func padded(_ pageNumber: Int, total pageTotal: Int) -> String {
        let validTotal = max(pageTotal, 1)
        let pageText = String(min(max(pageNumber, 1), validTotal))
        let digitCount = String(validTotal).count
        return String(
            repeating: "0",
            count: max(digitCount - pageText.count, 0),
        ) + pageText
    }

    /// 生成页码组件文本，并明确使用普通数字字符串避免本地化千分位分隔符。
    static func pageAndTotal(_ pageNumber: Int, total pageTotal: Int) -> String {
        let validTotal = max(pageTotal, 1)
        return "\(padded(pageNumber, total: validTotal))/\(String(validTotal))"
    }
}

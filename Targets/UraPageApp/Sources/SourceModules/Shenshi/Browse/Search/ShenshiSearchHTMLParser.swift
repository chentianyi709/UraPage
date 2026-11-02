import SwiftSoup

/// 将绅士移动端搜索结果 HTML 解析为普通漫画列表。
enum ShenshiSearchHTMLParser {
    /// 按网页顺序读取当前搜索页的全部可用卡片。
    static func items(from html: String) throws -> [ComicListItem] {
        do {
            let document = try SwiftSoup.parse(html)
            return try ShenshiComicListItemHTMLParser.items(in: document)
        } catch let error as ShenshiAPIError {
            throw error
        } catch {
            AppLogger.error(
                "搜索结果 HTML 解析失败，errorType=\(String(reflecting: type(of: error)))",
                category: "Shenshi.Search",
            )
            throw ShenshiAPIError.invalidResponse
        }
    }
}

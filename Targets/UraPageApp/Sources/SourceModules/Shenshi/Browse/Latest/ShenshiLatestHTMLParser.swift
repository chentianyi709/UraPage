import Foundation
import SwiftSoup

/// 将绅士漫画列表 HTML 解析为“最新”页面展示值。
enum ShenshiLatestHTMLParser {
    /// 解析一页漫画卡片和分页信息，并区分合法空页与网页结构失效。
    static func page(from html: String, currentPage: Int) throws -> ShenshiLatestPage {
        do {
            let document = try SwiftSoup.parse(html)
            guard let listContainer = try comicListContainer(in: document) else {
                AppLogger.error("移动版 HTML 缺少漫画列表容器", category: "Shenshi.Latest")
                throw ShenshiAPIError.invalidResponse
            }

            let cardElements = listContainer.children().filter { $0.tagName() == "li" }
            var items: [ComicListItem] = []

            // App 使用 iPhone User-Agent，服务端返回移动版页面；卡片位于该列表下。
            for element in cardElements {
                if let item = try ShenshiComicListItemHTMLParser.item(from: element) {
                    items.append(item)
                }
            }

            // 容器内没有卡片是合法空页；有卡片却全部失败才说明网页结构已变化。
            guard cardElements.isEmpty || !items.isEmpty else {
                AppLogger.error("移动版漫画卡片全部解析失败", category: "Shenshi.Latest")
                throw ShenshiAPIError.invalidResponse
            }

            return try ShenshiLatestPage(
                items: items,
                page: currentPage,
                totalPages: ShenshiListPaginationHTMLParser.totalPages(
                    from: document,
                    currentPage: currentPage,
                ),
                categories: ShenshiLatestCategoryHTMLParser.categories(from: document),
            )
        } catch let error as ShenshiAPIError {
            throw error
        } catch {
            AppLogger.error(
                "HTML 解析失败，errorType=\(String(reflecting: type(of: error)))",
                category: "Shenshi.Latest",
            )
            throw ShenshiAPIError.invalidResponse
        }
    }

    /// 优先使用稳定 ID，再寻找确实包含漫画详情链接的列表作为结构变化兜底。
    private static func comicListContainer(in document: Document) throws -> Element? {
        if let container = try document.select("#classify_container").first(),
           try !container.select("a[href*=\"photos-index-aid-\"]").isEmpty {
            return container
        }
        for list in try document.select("ul.col_2, ul") {
            if try !list.select("a[href*=\"photos-index-aid-\"]").isEmpty {
                return list
            }
        }
        return nil
    }
}

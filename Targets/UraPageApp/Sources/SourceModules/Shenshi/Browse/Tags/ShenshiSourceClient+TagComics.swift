import Alamofire
import SwiftSoup

extension ShenshiSourceClient {
    /// 请求详情页已解析的精确标签路径；第 N 页按网页分页协议改写 navigationKey。
    func tagComics(tag: ShenshiComicTag, page: Int) async throws -> ShenshiTagComicPage {
        let path = Self.tagPath(page: page, navigationKey: tag.navigationKey)

        return try await read { state in
            try await state.session
                .request("/\(path)")
                .shenshiParsedTextResponse { html in
                    try Self.tagPage(from: html, currentPage: page)
                }
        }
    }

    /// 标签列表第 1 页就是 navigationKey；后续页在 `albums-index-` 后插入 `page-N-`：
    /// `albums-index-tag-<name>.html` → `albums-index-page-N-tag-<name>.html`。
    private static func tagPath(page: Int, navigationKey: String) -> String {
        guard page > 1 else {
            return navigationKey
        }

        let prefix = "albums-index-"

        return prefix + "page-\(page)-" + navigationKey.dropFirst(prefix.count)
    }

    /// 标签卡片与其他普通网页列表同形；复用卡片解析与公共分页解析。
    private static func tagPage(from html: String, currentPage: Int) throws -> ShenshiTagComicPage {
        do {
            let document = try SwiftSoup.parse(html)
            let items = try ShenshiComicListItemHTMLParser.items(in: document)

            return try ShenshiTagComicPage(
                items: items,
                page: currentPage,
                totalPages: ShenshiListPaginationHTMLParser.totalPages(
                    from: document,
                    currentPage: currentPage,
                ),
            )
        } catch let error as ShenshiAPIError {
            throw error
        } catch {
            AppLogger.error("标签列表 HTML 解析失败", category: "Shenshi.Tag")
            throw ShenshiAPIError.invalidResponse
        }
    }
}

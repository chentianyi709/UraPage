import Alamofire
import SwiftSoup

extension ShenshiSourceClient {
    /// 请求发布者的移动端投稿页，读取同一发布者的可用分页游标。
    func publisherComics(
        publisher: ShenshiComicPublisher,
        cursor: String?,
    ) async throws -> ShenshiPublisherComicPage {
        let path = if let cursor {
            "albums-user-uid-\(publisher.id)-cursor-\(cursor).html"
        } else {
            "albums-user-uid-\(publisher.id).html"
        }

        return try await read { state in
            try await state.session
                .request("/\(path)")
                .shenshiParsedTextResponse { html in
                    try Self.publisherPage(from: html, publisherID: publisher.id)
                }
        }
    }

    /// 投稿页的漫画卡片与其他普通网页列表同形，复用现有卡片解析器。
    private static func publisherPage(
        from html: String,
        publisherID: String,
    ) throws -> ShenshiPublisherComicPage {
        do {
            let document = try SwiftSoup.parse(html)
            let items = try ShenshiComicListItemHTMLParser.items(in: document)
            // TODO: 拿到同时包含前页与后页的真实 HTML 后，按网页标记只识别后页。
            // 目前 URL 只能证明链接属于当前发布者，不能证明它指向后页。
            let nextCursor = try document
                .select("a[href*=\"albums-user-uid-\"]")
                .compactMap { link -> String? in
                    let href = try link.attr("href")
                    guard let match = href.firstMatch(
                        of: #/(?:^|/)albums-user-uid-([0-9]+)-cursor-([0-9]+)\.html(?:[?#].*)?$/#,
                    ), String(match.1) == publisherID else {
                        return nil
                    }

                    return String(match.2)
                }
                .first
            return ShenshiPublisherComicPage(items: items, nextCursor: nextCursor)
        } catch let error as ShenshiAPIError {
            throw error
        } catch {
            AppLogger.error("投稿列表 HTML 解析失败，uid=\(publisherID)", category: "Shenshi.Publisher")
            throw ShenshiAPIError.invalidResponse
        }
    }
}

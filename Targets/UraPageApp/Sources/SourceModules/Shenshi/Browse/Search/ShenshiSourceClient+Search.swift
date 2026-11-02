import Alamofire
import Foundation

extension ShenshiSourceClient {
    /// 按移动网页表单协议请求指定关键词和页码的搜索结果。
    func searchComics(query: String, page: Int) async throws -> [ComicListItem] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            throw ShenshiAPIError.invalidArgument
        }

        return try await read { state in
            try await state.session
                .request(
                    "/q/index.php",
                    parameters: [
                        "q": trimmedQuery,
                        "m": "",
                        "f": "_all",
                        "syn": "yes",
                        "s": "create_time_DESC",
                        "p": String(page),
                    ],
                    encoding: URLEncoding.default,
                )
                .shenshiParsedTextResponse { html in
                    try ShenshiSearchHTMLParser.items(from: html)
                }
        }
    }
}

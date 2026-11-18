import Alamofire
import Foundation

extension ShenshiSourceClient {
    /// 请求绅士移动端评论页；回复随页面一起返回。
    func comments(comicID: String) async throws -> ComicCommentPage {
        guard !comicID.isEmpty, comicID.utf8.allSatisfy({ (48 ... 57).contains($0) }) else {
            throw ComicSourceError.invalidIdentity
        }

        let path = "comment-index-aid-\(comicID).html"
        return try await read { state in
            try await state.session
                .request("/\(path)")
                .shenshiParsedTextResponse { html in
                    try ShenshiCommentHTMLParser.page(from: html)
                }
        }
    }
}

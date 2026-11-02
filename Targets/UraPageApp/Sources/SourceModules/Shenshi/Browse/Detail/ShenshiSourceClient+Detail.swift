import Alamofire
import Foundation

extension ShenshiSourceClient {
    /// 请求绅士移动端漫画详情 HTML，并转换为来源专属展示模型。
    func detail(comicID: String) async throws -> ShenshiComicDetail {
        let path = try Self.detailPath(for: comicID)
        return try await read { state in
            try await state.session
                .request("/\(path)")
                .shenshiParsedTextResponse { html in
                    try ShenshiComicDetailHTMLParser.detail(from: html, comicID: comicID)
                }
        }
    }

    /// 使用操作发生时的当前 Base URL 生成一个可分享的完整详情地址。
    func detailPageURL(comicID: String) async throws -> URL {
        let path = try Self.detailPath(for: comicID)
        let state = try await preparedState()
        try Task.checkCancellation()
        return state.baseURL.appending(path: path)
    }

    /// 校验作品 ID，并返回详情请求与复制链接共同使用的相对路径。
    private static func detailPath(for comicID: String) throws -> String {
        guard !comicID.isEmpty, comicID.utf8.allSatisfy({ (48 ... 57).contains($0) }) else {
            throw ComicSourceError.invalidIdentity
        }

        return "photos-index-aid-\(comicID).html"
    }
}

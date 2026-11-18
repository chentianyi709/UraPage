import Alamofire
import Foundation

extension JMComicSourceClient {
    /// 请求禁漫指定作品的一页评论；回复随顶级评论一起返回。
    func comments(comicID: String, page: Int) async throws -> ComicCommentPage {
        guard !comicID.isEmpty, page >= 1 else {
            throw JMComicAPIError.invalidArgument
        }

        let response = try await read { state in
            try await state.session
                .request(
                    "/forum",
                    method: .get,
                    parameters: [
                        "mode": "all",
                        "page": String(page),
                        "aid": comicID,
                    ],
                    encoding: URLEncoding.default,
                )
                .jmComicDecodedResponse(as: JMComicCommentsResponseDTO.self)
        }

        return makeJMComicCommentPage(from: response)
    }
}

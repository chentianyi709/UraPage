import Alamofire
import Foundation

extension BikaSourceClient {
    /// 请求哔咔指定作品的一页顶级评论。
    func comments(comicID: String, page: Int) async throws -> ComicCommentPage {
        guard !comicID.isEmpty else {
            throw BikaAPIError.invalidArgument
        }

        return try await commentPage(path: "comics/\(comicID)/comments", page: page)
    }

    /// 请求哔咔指定顶级评论的一页子评论。
    func commentReplies(commentID: String, page: Int) async throws -> ComicCommentPage {
        guard !commentID.isEmpty else {
            throw BikaAPIError.invalidArgument
        }

        return try await commentPage(path: "comments/\(commentID)/childrens", page: page)
    }

    /// 两种评论接口共用的分页请求与来源映射。
    private func commentPage(path: String, page: Int) async throws -> ComicCommentPage {
        guard page >= 1 else {
            throw BikaAPIError.invalidArgument
        }

        let response = try await read { state in
            try await state.session
                .request(
                    path,
                    method: .get,
                    parameters: ["page": page],
                    encoding: URLEncoding(destination: .queryString),
                )
                .bikaDecodedResponse(as: BikaComicCommentsResponseDTO.self)
        }
        .comments

        return makeBikaComicCommentPage(from: response)
    }
}

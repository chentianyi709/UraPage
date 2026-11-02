import Alamofire
import Foundation

extension BikaSourceClient {
    /// 请求指定章节顺序号的一个接口分页及真实总图片数。
    func chapterContent(
        for identity: ChapterIdentity,
        order: Int,
        page: Int = 1,
    ) async throws -> BikaResolvedChapterContent {
        // 章节 identity 与 order 已由公开 Service 入口完成边界校验。
        let response = try await chapterPage(comicID: identity.comic.comicID, order: order, page: page)
        return try makeBikaResolvedChapterContent(from: response, identity: identity)
    }

    /// 请求一个经过响应包装校验的章节图片页。
    private func chapterPage(comicID: String, order: Int, page: Int) async throws -> BikaChapterPagesDTO {
        let response = try await read { state in
            try await state.session
                .request(
                    "comics/\(comicID)/order/\(order)/pages",
                    method: .get,
                    parameters: ["page": page],
                    encoding: URLEncoding(destination: .queryString),
                    headers: ["image-quality": BikaImageQuality.original.rawValue],
                )
                .bikaDecodedResponse(as: BikaChapterContentResponseDTO.self)
        }
        return response.pages
    }
}

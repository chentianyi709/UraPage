import Alamofire

extension JMComicSourceClient {
    /// 请求禁漫章节页面清单，并在 Source Target 内解析页面地址。
    func chapterContent(for identity: ChapterIdentity) async throws -> JMComicResolvedChapterContent {
        try await read { state in
            let response = try await state.session
                .request(
                    "/comic_read",
                    method: .get,
                    parameters: ["id": identity.chapterID],
                    encoding: URLEncoding.default,
                )
                .jmComicDecodedResponse(as: JMComicChapterContentDTO.self)

            return try makeJMResolvedChapterContent(
                from: response,
                identity: identity,
                imageHost: state.setting.imageHost,
            )
        }
    }
}

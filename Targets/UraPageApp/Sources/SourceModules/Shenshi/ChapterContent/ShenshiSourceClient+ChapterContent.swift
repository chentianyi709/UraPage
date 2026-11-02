import Alamofire

extension ShenshiSourceClient {
    /// 请求绅士 Reader 数据脚本，并解析当前作品的有序页面清单。
    func chapterContent(for identity: ChapterIdentity) async throws -> ShenshiResolvedChapterContent {
        // 来源、章节归属和数字格式已由公开 Service 入口完成边界校验。
        let comicID = identity.comic.comicID
        let path = "photos-item-aid-\(comicID).html"

        return try await read { state in
            try await state.session
                .request("/\(path)")
                .shenshiParsedTextResponse { script in
                    let pageURLStrings = try ShenshiReaderScriptParser.pageURLStrings(from: script)
                    return try makeShenshiResolvedChapterContent(
                        from: pageURLStrings,
                        identity: identity,
                        baseURL: state.baseURL,
                        userAgent: state.userAgent,
                    )
                }
        }
    }
}

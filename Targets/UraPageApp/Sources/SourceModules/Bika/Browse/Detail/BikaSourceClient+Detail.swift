import Alamofire

extension BikaSourceClient {
    /// 获取漫画详情和全部章节页，并映射为单个详情展示值。
    func detail(for identity: ComicIdentity) async throws -> BikaComicDetail {
        async let response = detailResponse(comicID: identity.comicID)
        async let chapters = episodeDTOs(for: identity.comicID)
        let (resolvedResponse, resolvedChapters) = try await (response, chapters)

        return try makeBikaComicDetail(
            from: resolvedResponse.comic,
            chapterDTOs: resolvedChapters,
            requestedIdentity: identity,
        )
    }

    /// 请求一份经过响应包装校验的漫画主详情。
    private func detailResponse(comicID: String) async throws -> BikaComicDetailResponseDTO {
        try await read { state in
            try await state.session
                .request("comics/\(comicID)", method: .get)
                .bikaDecodedResponse(as: BikaComicDetailResponseDTO.self)
        }
    }

    /// 顺序请求全部章节分页，不使用无界并发。
    private func episodeDTOs(for comicID: String) async throws -> [BikaEpisodeDTO] {
        let firstPage = try await episodePage(comicID: comicID, page: 1)
        return try await allPagedDocuments(firstPage: firstPage) { page in
            try await episodePage(comicID: comicID, page: page)
        }
    }

    /// 请求并返回一个经过响应包装校验的章节页。
    private func episodePage(comicID: String, page: Int) async throws -> BikaEpisodesPageDTO {
        let response = try await read { state in
            try await state.session
                .request(
                    "comics/\(comicID)/eps",
                    method: .get,
                    parameters: ["page": page],
                    encoding: URLEncoding(destination: .queryString),
                )
                .bikaDecodedResponse(as: BikaEpisodesResponseDTO.self)
        }
        return response.eps
    }
}

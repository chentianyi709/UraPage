import Alamofire

extension BikaSourceClient {
    /// 获取哔咔当前的热门搜索推荐词。
    func searchRecommendations() async throws -> [String] {
        let response = try await read { state in
            try await state.session
                .request("keywords", method: .get)
                .bikaDecodedResponse(as: BikaSearchRecommendationsDTO.self)
        }
        return response.keywords
    }

    /// 使用关键词、排序和可选多分类过滤搜索一页漫画。
    func searchComics(
        query: String,
        sort: BikaComicSort,
        categories: [BikaComicCategory],
        page: Int,
    ) async throws -> BikaComicPage {
        guard !query.isEmpty else {
            throw BikaAPIError.invalidArgument
        }

        let request = BikaAdvancedSearchRequestDTO(
            keyword: query,
            sort: sort.requestValue,
            categories: categories.isEmpty ? nil : categories.map(\.title),
        )
        let response = try await read { state in
            try await state.session
                .request(
                    "comics/advanced-search?page=\(page)",
                    method: .post,
                    parameters: request,
                    encoder: JSONParameterEncoder.default,
                    headers: nil,
                    interceptor: nil,
                    requestModifier: nil,
                )
                .bikaDecodedResponse(as: BikaComicListResponseDTO.self)
        }

        return try makeBikaComicPage(from: response.comics, expectedPage: page)
    }
}

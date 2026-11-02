import Alamofire

extension BikaSourceClient {
    /// 按分类、标签或贡献者筛选条件获取一页漫画；`filter` 为 `nil` 时不带筛选参数（服务端默认列表）。
    func filteredComics(
        filter: BikaComicListFilter?,
        sort: BikaComicSort,
        page: Int,
    ) async throws -> BikaComicPage {
        let parameters: [String: String]
        if let filterParameter = filter?.requestParameter {
            parameters = [
                "page": String(page),
                "s": sort.requestValue,
                filterParameter.key: filterParameter.value,
            ]
        } else {
            parameters = [
                "page": String(page),
                "s": sort.requestValue,
            ]
        }

        let response = try await read { state in
            try await state.session
                .request(
                    "comics",
                    method: .get,
                    parameters: parameters,
                    encoding: URLEncoding(destination: .queryString),
                )
                .bikaDecodedResponse(as: BikaComicListResponseDTO.self)
        }

        return try makeBikaComicPage(from: response.comics, expectedPage: page)
    }
}

import Alamofire

extension JMComicSourceClient {
    /// 请求禁漫漫画详情，并转换为不暴露接口字段的展示模型。
    func detail(comicID: String) async throws -> JMComicDetail {
        let detail = try await read { state in
            try await state.session
                .request(
                    "/album",
                    method: .get,
                    parameters: ["id": comicID],
                    encoding: URLEncoding.default,
                )
                .jmComicDecodedResponse(as: JMComicDetailDTO.self)
        }
        return try makeJMComicDetail(from: detail)
    }
}

import Alamofire

extension BikaSourceClient {
    /// 获取服务端当次生成的随机漫画，保留出现顺序。
    ///
    /// 单次请求的静态列表，不做去重；单张坏卡片不影响其它有效作品。
    func randomComics() async throws -> [ComicListItem] {
        let response = try await read { state in
            try await state.session
                .request("comics/random", method: .get)
                .bikaDecodedResponse(as: BikaRandomComicsResponseDTO.self)
        }

        // 单次请求的静态列表不做去重；坏卡片只跳过自身。
        return SourceItemMapping
            .compactMap(response.comics, category: "Bika.Home") { makeBikaComicListItem(from: $0) }
    }
}

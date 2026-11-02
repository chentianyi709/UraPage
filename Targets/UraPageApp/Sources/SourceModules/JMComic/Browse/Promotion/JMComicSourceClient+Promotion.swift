import Alamofire

extension JMComicSourceClient {
    /// 获取禁漫首页指定普通推广分区的一页漫画。
    ///
    /// 页码从 0 开始（服务端如此）；是否还有下一页由服务端总数判断。
    /// 分页列表不在来源层去重；单张坏卡片跳过。
    func promotionComics(
        sectionID: String,
        page: Int,
    ) async throws -> JMComicPromotionComicPage {
        let response = try await read { state in
            try await state.session
                .request(
                    "/promote_list",
                    method: .get,
                    parameters: [
                        "id": sectionID,
                        "page": page,
                    ],
                    encoding: URLEncoding.default,
                )
                .jmComicDecodedResponse(as: JMComicPromotionResponseDTO.self)
        }

        let comics = SourceItemMapping
            .compactMap(response.list, category: "JM.Promotion") { makeJMComicListItem(from: $0) }
        return JMComicPromotionComicPage(comics: comics, total: response.total)
    }
}

import Alamofire

extension JMComicSourceClient {
    /// 获取禁漫指定内容类型、日期和页码的周刊漫画。
    ///
    /// 分页列表不在来源层去重；单张坏卡片跳过。`hasMore` 用当前页条目数量判断。
    func weeklyComics(
        type: JMComicWeeklyContentType,
        date: JMComicWeeklyDate,
        page: Int,
    ) async throws -> JMComicWeeklyComicPage {
        let response = try await read { state in
            try await state.session
                .request(
                    "/serialization",
                    method: .get,
                    parameters: [
                        "type": type.rawValue,
                        "date": date.rawValue,
                        "page": page,
                    ],
                    encoding: URLEncoding.default,
                )
                .jmComicDecodedResponse(as: JMComicWeeklyResponseDTO.self)
        }

        let comics = SourceItemMapping
            .compactMap(response.list, category: "JM.Weekly") { makeJMComicListItem(from: $0) }
        return JMComicWeeklyComicPage(
            comics: comics,
            hasMore: response.list.count >= JMComicConfiguration.Browse.weeklyPageSize,
        )
    }
}

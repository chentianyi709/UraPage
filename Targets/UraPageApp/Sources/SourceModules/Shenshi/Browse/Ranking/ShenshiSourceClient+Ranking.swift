import Alamofire

extension ShenshiSourceClient {
    /// 请求指定周期、内容分类和页码的绅士收藏排行榜。
    func ranking(
        period: ShenshiRankingPeriod,
        categoryID: Int?,
        page: Int,
    ) async throws -> ShenshiRankingPage {
        let path = Self.rankingPath(period: period, categoryID: categoryID, page: page)
        return try await read { state in
            try await state.session
                .request("/\(path)")
                .shenshiParsedTextResponse { html in
                    try ShenshiRankingHTMLParser.page(from: html, currentPage: page)
                }
        }
    }

    /// 按网页协议生成排行榜筛选和分页路径。
    private static func rankingPath(
        period: ShenshiRankingPeriod,
        categoryID: Int?,
        page: Int,
    ) -> String {
        if page == 1 {
            let categoryPart = categoryID.map { "-cate-\($0)" } ?? "-cate"
            return "albums-favorite_ranking-type-\(period.requestValue)\(categoryPart).html"
        }

        let categoryPart = categoryID.map { "-cate-\($0)" } ?? ""
        return "albums-favorite_ranking-page-\(page)-type-\(period.requestValue)\(categoryPart).html"
    }
}

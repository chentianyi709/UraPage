import Alamofire

extension ShenshiSourceClient {
    /// 请求绅士指定分类和页码的更新漫画 HTML，并转换为页面展示值。
    func latest(page: Int, categoryID: Int?) async throws -> ShenshiLatestPage {
        let path = Self.latestPath(page: page, categoryID: categoryID)

        return try await read { state in
            try await state.session
                .request("/\(path)")
                .shenshiParsedTextResponse { html in
                    try ShenshiLatestHTMLParser.page(from: html, currentPage: page)
                }
        }
    }

    /// 按网页真实协议生成全部更新或指定分类的分页路径。
    private static func latestPath(page: Int, categoryID: Int?) -> String {
        guard let categoryID else {
            return page == 1 ? "albums.html" : "albums-index-page-\(page).html"
        }

        return page == 1
            ? "albums-index-cate-\(categoryID).html"
            : "albums-index-page-\(page)-cate-\(categoryID).html"
    }
}

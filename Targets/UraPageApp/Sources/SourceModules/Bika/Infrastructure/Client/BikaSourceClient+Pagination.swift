import Alamofire

/// 哔咔分页响应的公共形状：页码、总页数与本页条目。
///
/// 章节列表与章节内容两个接口的响应结构一致，用本协议让分页边界校验只实现一次。
protocol BikaPagedResponse {
    associatedtype Element

    var page: Int { get }
    var pages: Int { get }
    var docs: [Element] { get }
}

extension BikaSourceClient {
    /// 顺序请求全部分页并合并 `docs`，不使用无界并发。
    ///
    /// 首页必须从第 1 页开始；后续每一页都必须与首页的 `page`/`pages` 对齐，
    /// 否则视为分页错位并暴露响应级错误（不猜测、不补齐）。
    func allPagedDocuments<Page: BikaPagedResponse>(
        firstPage: Page,
        fetch: (_ page: Int) async throws -> Page,
    ) async throws -> [Page.Element] {
        guard firstPage.page == 1, firstPage.pages > 0 || firstPage.docs.isEmpty else {
            throw BikaAPIError.invalidResponse
        }

        var documents = firstPage.docs
        guard firstPage.pages > 1 else {
            return documents
        }

        for page in 2 ... firstPage.pages {
            try Task.checkCancellation()
            let response = try await fetch(page)
            guard response.page == page, response.pages == firstPage.pages else {
                throw BikaAPIError.invalidResponse
            }

            documents.append(contentsOf: response.docs)
        }

        return documents
    }
}

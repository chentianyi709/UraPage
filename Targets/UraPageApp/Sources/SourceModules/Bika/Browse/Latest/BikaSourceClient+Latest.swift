import Alamofire

extension BikaSourceClient {
    /// 使用哔咔“新到旧”排序获取一页最近更新漫画（不带分类筛选）。
    ///
    /// 请求实现与 `filteredComics` 共用，避免同一 `comics` 请求写两遍。
    func recentlyUpdatedComics(page: Int) async throws -> BikaComicPage {
        try await filteredComics(filter: nil, sort: .latest, page: page)
    }
}

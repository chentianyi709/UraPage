import Foundation
import Observation

/// 绅士搜索页的页面级状态：搜索输入与结果分页。
///
/// 页面首次展示时由视图创建（Services 来自本源 Environment），销毁时一并取消在途请求。
@MainActor
@Observable
final class ShenshiSearchModel {
    /// 搜索框文本（`.searchable` 绑定）。
    var searchText = ""

    /// 已提交的关键词；`nil` 表示还没搜索，页面显示搜索引导空态。
    private(set) var query: String?

    /// 结果分页执行器；只在提交过关键词后由列表视图驱动加载。
    let paging: ComicPagingModel<String, Int>

    init(services: ShenshiServices) {
        paging = ComicPagingModel { query, cursor in
            let requestedPage = cursor ?? 1
            let items = try await services.searchComics(query: query, page: requestedPage)

            // 搜索响应没有总页数：按“本页是否产生新条目”续载（空页即尾页，与本源其它列表页一致）。
            return ComicPageSlice(
                items: items,
                continuation: .whileMakingProgress(cursor: requestedPage + 1),
            )
        }
    }

    /// 提交搜索框里的关键词；相同查询不重发（失败态由结果区的重试按钮重新请求）。
    func submitSearch() {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            clearSearch()
            return
        }

        searchText = trimmed
        guard trimmed != query else {
            return
        }

        query = trimmed
    }

    /// 清空搜索框：取消结果、回到搜索引导态。
    func clearSearch() {
        paging.reset()
        searchText = ""
        query = nil
    }
}

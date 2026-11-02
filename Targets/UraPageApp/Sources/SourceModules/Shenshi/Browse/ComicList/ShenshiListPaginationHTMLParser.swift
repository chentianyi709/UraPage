import Foundation
import SwiftSoup

/// 绅士网页列表分页区域的公共解析：更新、分类与标签列表共用同一分页块。
///
/// 分页链接路径按列表类型带不同后缀：
/// - 全部更新：`albums-index-page-{page}.html`
/// - 分类：`albums-index-page-{page}-cate-{id}.html`
/// - 标签：`albums-index-page-{page}-tag-{name}.html`
enum ShenshiListPaginationHTMLParser {
    /// 从分页链接和当前页节点读取最大页码；无法识别时不伪造总页数。
    ///
    /// 页码取 URL 里的 `albums-index-page-{page}`，不要求链接文案是数字：分页块里的
    /// “下一页”/“上一页”文案不是数字，但 href 仍是真实页面；只看数字文案会把“只有
    /// 下一页链接”的小列表误判成已到末页。上一页链接不会被当成最大值；只有“下一页”
    /// 时最大页码是当前页 +1，列表会在下一页继续重新计算，最终在真正末页停止。
    static func totalPages(from document: Document, currentPage: Int) throws -> Int? {
        let pagination = try document.select(".block-pagination").first()
        let linkScope = pagination ?? document
        var pages: [Int] = []

        for link in try linkScope.select("a[href*=\"albums-index-page-\"]") {
            if let pathPage = try page(from: link.attr("href")) {
                pages.append(pathPage)
            }
        }

        // 最后一页没有指向自己的链接，只会通过当前页节点声明页码。
        if let pagination,
           let currentPageText = try pagination.select(".thispage").first()?.text(),
           let declaredCurrentPage = Int(currentPageText) {
            pages.append(declaredCurrentPage)
        }

        guard let maximumPage = pages.max(), maximumPage >= currentPage else {
            AppLogger.debug("未识别分页总页数，page=\(currentPage)", category: "Shenshi.List")
            return nil
        }

        return maximumPage
    }

    /// 从全部更新、分类或标签分页 URL 中提取 `albums-index-page-{page}` 的数字页码。
    private static func page(from href: String) -> Int? {
        guard let match = href.firstMatch(
            of: #/(?:^|/)albums-index-page-([0-9]+)(?:-(?:cate-[0-9]+|tag-[^/?#\\\r\n]+))?\.html(?:[?#].*)?$/#,
        ) else {
            return nil
        }

        return Int(match.1)
    }
}

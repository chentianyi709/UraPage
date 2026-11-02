import Foundation
import SwiftSoup

/// 将绅士移动版收藏排行榜 HTML 转换为页面展示值。
enum ShenshiRankingHTMLParser {
    /// 解析排行榜卡片、内容分类和分页信息。
    static func page(from html: String, currentPage: Int) throws -> ShenshiRankingPage {
        do {
            let document = try SwiftSoup.parse(html)
            guard let container = try document.select("#topImgCon").first() else {
                AppLogger.error("排行榜 HTML 缺少卡片容器", category: "Shenshi.Ranking")
                throw ShenshiAPIError.invalidResponse
            }

            let cardElements = try Array(container.select(".itemBox"))
            let items = try cardElements.compactMap {
                try ShenshiComicListItemHTMLParser.item(from: $0)
            }

            // 有卡片却全部失败，说明网页结构已变化。
            guard cardElements.isEmpty || !items.isEmpty else {
                AppLogger.error("排行榜漫画卡片全部解析失败", category: "Shenshi.Ranking")
                throw ShenshiAPIError.invalidResponse
            }

            return try ShenshiRankingPage(
                items: items,
                page: currentPage,
                totalPages: totalPages(from: document, currentPage: currentPage),
                categories: categories(from: document),
            )
        } catch let error as ShenshiAPIError {
            throw error
        } catch {
            AppLogger.error(
                "排行榜 HTML 解析失败，errorType=\(String(reflecting: type(of: error)))",
                category: "Shenshi.Ranking",
            )
            throw ShenshiAPIError.invalidResponse
        }
    }

    /// 按网页平行的父分类名称和选项组恢复两级分类。
    private static func categories(from document: Document) -> [ShenshiRankingCategory] {
        do {
            let titles = try Array(document.select("#cateLeftTit > li")).dropFirst()
            let groups = try Array(document.select("#cateRightCon > ul")).dropFirst()

            return try zip(titles, groups).compactMap { pair -> ShenshiRankingCategory? in
                let (titleElement, group) = pair
                let links = try Array(group.select("a[href*='albums-favorite_ranking'][href*='-cate-']"))
                guard let parentLink = links.first,
                      let parentID = try categoryID(from: parentLink.attr("href"))
                else {
                    return nil
                }

                let title = try titleElement.text()
                guard !title.isEmpty else {
                    return nil
                }

                let children = try links.dropFirst().compactMap { link -> ShenshiRankingCategory? in
                    guard let id = try categoryID(from: link.attr("href")) else {
                        return nil
                    }

                    let childTitle = try link.text()
                    guard !childTitle.isEmpty else {
                        return nil
                    }

                    return ShenshiRankingCategory(id: id, title: childTitle, children: [])
                }

                return ShenshiRankingCategory(id: parentID, title: title, children: children)
            }
        } catch {
            AppLogger.warning(
                "排行榜分类解析失败，errorType=\(String(reflecting: type(of: error)))",
                category: "Shenshi.Ranking",
            )
            return []
        }
    }

    /// 从排行榜分类链接读取数字分类 ID。
    private static func categoryID(from href: String) -> Int? {
        guard let match = href.firstMatch(of: #/-cate-([0-9]+)\.html(?:[?#].*)?$/#) else {
            return nil
        }

        return Int(match.1)
    }

    /// 从数字分页链接读取网页声明的最大页码。
    private static func totalPages(from document: Document, currentPage: Int) throws -> Int? {
        var pages: [Int] = []

        for link in try document.select("a[href*='albums-favorite_ranking-page-']") {
            let href = try link.attr("href")
            let text = try link.text()
            if let pathPage = paginationPage(from: href), let labelPage = Int(text), pathPage == labelPage {
                pages.append(pathPage)
            }
        }

        if let currentPageText = try document.select(".block-pagination .thispage").first()?.text(),
           let declaredCurrentPage = Int(currentPageText) {
            pages.append(declaredCurrentPage)
        }

        guard let maximumPage = pages.max(), maximumPage >= currentPage else {
            return nil
        }

        return maximumPage
    }

    /// 从排行榜分页 URL 中提取页码。
    private static func paginationPage(from href: String) -> Int? {
        guard let match = href.firstMatch(
            of: #/(?:^|/)albums-favorite_ranking-page-([0-9]+)-type-(?:day|week|month|year)(?:-cate-[0-9]+)?\.html(?:[?#].*)?$/#,
        ) else {
            return nil
        }

        return Int(match.1)
    }
}

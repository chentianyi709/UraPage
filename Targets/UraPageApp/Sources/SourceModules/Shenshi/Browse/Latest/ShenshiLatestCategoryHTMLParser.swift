import Foundation
import SwiftSoup

/// 从绅士更新页面的移动版导航区域解析两级分类。
enum ShenshiLatestCategoryHTMLParser {
    /// 返回可用分类；分类区域单独失效时保留漫画列表，只隐藏本次菜单数据。
    static func categories(from document: Document) -> [ShenshiLatestCategory] {
        do {
            let categories = try parsedCategories(from: document)
            if categories.isEmpty {
                AppLogger.warning("移动版 HTML 未识别到分类菜单", category: "Shenshi.Latest")
            }
            return categories
        } catch {
            AppLogger.warning(
                "HTML 分类解析失败，errorType=\(String(reflecting: type(of: error)))",
                category: "Shenshi.Latest",
            )
            return []
        }
    }

    /// 按移动版平行的标题列表和选项列表恢复两级分类。
    private static func parsedCategories(from document: Document) throws -> [ShenshiLatestCategory] {
        let scope = try mobileCategoryScope(in: document) ?? document
        let titles = try Array(scope.select("#classTit > li, .OperaBar > li"))
        let optionGroups = try Array(scope.select("#classCon > ul, .classopen > ul"))
        guard !titles.isEmpty, !optionGroups.isEmpty else {
            return []
        }

        var categories: [ShenshiLatestCategory] = []
        var categoryIDs = Set<Int>()

        for (titleElement, optionGroup) in zip(titles, optionGroups) {
            let links = try Array(optionGroup.select("a[href*=\"albums-index-cate-\"]"))
            guard let parentLink = links.first,
                  let parentID = try categoryID(from: parentLink.attr("href")),
                  categoryIDs.insert(parentID).inserted
            else {
                continue
            }

            let parentTitle = try titleElement.text()
            guard !parentTitle.isEmpty else {
                continue
            }

            var children: [ShenshiLatestCategory] = []
            for childLink in links.dropFirst() {
                guard let child = try category(from: childLink),
                      categoryIDs.insert(child.id).inserted
                else {
                    continue
                }

                children.append(child)
            }

            categories.append(
                ShenshiLatestCategory(id: parentID, title: parentTitle, children: children),
            )
        }

        return categories
    }

    /// 优先把选择器限制在真正包含分类链接的移动版分类容器中。
    private static func mobileCategoryScope(in document: Document) throws -> Element? {
        for element in try document.select(".classBox") {
            if try !element.select("a[href*=\"albums-index-cate-\"]").isEmpty {
                return element
            }
        }
        return nil
    }

    /// 从一个分类链接读取数字 ID 和页面原始名称。
    static func category(from link: Element) throws -> ShenshiLatestCategory? {
        guard let id = try categoryID(from: link.attr("href")) else {
            return nil
        }

        let title = try link.text()
        guard !title.isEmpty else {
            return nil
        }

        return ShenshiLatestCategory(id: id, title: title, children: [])
    }

    /// 从相对或完整分类 URL 中提取 `albums-index-cate-{id}` 的数字分类 ID。
    static func categoryID(from href: String) -> Int? {
        guard let match = href.firstMatch(
            of: #/(?:^|/)albums-index-cate-([0-9]+)\.html(?:[?#].*)?$/#,
        ), let categoryID = Int(match.1), categoryID > 0 else {
            return nil
        }

        return categoryID
    }
}

import SwiftSoup

/// 将绅士移动端首页 HTML 解析为推荐页分区。
enum ShenshiHomeHTMLParser {
    private static let maximumItemCountPerSection = 6

    /// 解析页面中仍能正确配对的分区标题和漫画列表。
    static func sections(from html: String) throws -> [ShenshiHomeSection] {
        do {
            let document = try SwiftSoup.parse(html)
            var sections: [ShenshiHomeSection] = []

            for container in try document.select("div.imgBox") {
                // 标题、列表和至少一个详情链接必须同时存在，才认为分区完整。
                guard let titleContainer = try container.select(".Sub_H2").first(),
                      let list = try container.select("ul.col_3_2").first(),
                      try !list.select("a[href*=\"photos-index-aid-\"]").isEmpty,
                      let title = try sectionTitle(from: titleContainer)
                else {
                    continue
                }

                let items = try items(from: list)
                guard !items.isEmpty else {
                    continue
                }

                try sections.append(
                    ShenshiHomeSection(
                        id: title,
                        title: title,
                        items: items,
                        navigation: navigation(from: titleContainer),
                    ),
                )
            }

            guard !sections.isEmpty else {
                AppLogger.error("移动版首页未解析到有效推荐分区", category: "Shenshi.Recommended")
                throw ShenshiAPIError.invalidResponse
            }

            return sections
        } catch let error as ShenshiAPIError {
            throw error
        } catch {
            AppLogger.error(
                "推荐页 HTML 解析失败，errorType=\(String(reflecting: type(of: error)))",
                category: "Shenshi.Recommended",
            )
            throw ShenshiAPIError.invalidResponse
        }
    }

    /// 读取移动版分区标题，并在内部标题 class 微调时回退到标题容器文本。
    private static func sectionTitle(from container: Element) throws -> String? {
        if let titleElement = try container.select(".Title").first() {
            let title = try normalizedText(titleElement.text())
            if !title.isEmpty {
                return title
            }
        }
        let fallbackTitle = try normalizedText(container.text())
        guard !fallbackTitle.isEmpty else {
            return nil
        }

        return fallbackTitle
    }

    /// 把分区标题区域的普通更新或分类更新链接转换为来源专属导航语义。
    private static func navigation(from container: Element) throws -> ShenshiHomeSectionNavigation {
        var hasUnfilteredUpdatesLink = false

        for link in try container.select("a[href]") {
            let href = try link.attr("href")
            if let categoryID = ShenshiLatestCategoryHTMLParser.categoryID(from: href) {
                return .updates(categoryID: categoryID)
            }
            if isUnfilteredUpdatesPath(href) {
                hasUnfilteredUpdatesLink = true
            }
        }

        return hasUnfilteredUpdatesLink ? .updates(categoryID: nil) : .none
    }

    /// 只接受移动端真实的普通更新路径，不把其它相似链接误判为更新入口。
    private static func isUnfilteredUpdatesPath(_ href: String) -> Bool {
        href.firstMatch(of: #/(?:^|/)albums\.html(?:[?#].*)?$/#) != nil
    }

    /// 跳过单个坏卡片，按网页顺序收集最多六个有效漫画；静态分区不额外去重。
    private static func items(from list: Element) throws -> [ComicListItem] {
        var items: [ComicListItem] = []

        for element in list.children() where element.tagName() == "li" {
            guard let item = try ShenshiComicListItemHTMLParser.item(from: element) else {
                continue
            }

            items.append(item)
            if items.count == maximumItemCountPerSection {
                break
            }
        }
        return items
    }

    /// 合并 HTML 中用于排版的空白，但不改变真实标题内容。
    private static func normalizedText(_ value: String) -> String {
        value.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}

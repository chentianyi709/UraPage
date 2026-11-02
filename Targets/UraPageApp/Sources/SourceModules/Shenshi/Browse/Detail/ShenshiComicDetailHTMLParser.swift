import Foundation
import SwiftSoup

/// 将绅士移动端详情 HTML 解析为来源专属展示模型。
enum ShenshiComicDetailHTMLParser {
    /// 读取详情必要字段，并允许发布者、分类、图片数量和附加分区独立缺失。
    static func detail(from html: String, comicID: String) throws -> ShenshiComicDetail {
        do {
            let document = try SwiftSoup.parse(html)
            let detailScope = try document.select(".Introduct_Sub").first() ?? document

            // 封面是详情必要内容；没有任何非空封面图说明页面结构已变化。
            let coverCandidates = try Array(detailScope.select("#Cover img[src], .pic img[src]"))
            guard let coverImage = try coverCandidates.first(where: { try !$0.attr("src").isEmpty }) else {
                throw ShenshiAPIError.invalidResponse
            }

            let coverLocator = try coverImage.attr("src")
            let title = try comicTitle(from: document, coverImage: coverImage)
            guard !title.isEmpty else {
                throw ShenshiAPIError.invalidResponse
            }

            return try ShenshiComicDetail(
                identity: ComicIdentity(sourceID: .shenshi, comicID: comicID),
                title: title,
                publisher: publisher(in: detailScope),
                category: category(in: detailScope),
                pageCount: pageCount(in: detailScope),
                commentCount: commentCount(in: document, comicID: comicID),
                summary: summary(in: document),
                comicTags: tags(in: document),
                cover: .remote(
                    ComicImageReference(
                        sourceID: .shenshi,
                        ownerID: comicID,
                        locator: coverLocator,
                        purpose: .cover,
                        variant: nil,
                    ),
                ),
                relatedComics: relatedComics(in: document),
            )
        } catch let error as ShenshiAPIError {
            throw error
        } catch {
            AppLogger.error(
                "详情 HTML 解析失败，id=\(comicID)，errorType=\(String(reflecting: type(of: error)))",
                category: "Shenshi.Detail",
            )
            throw ShenshiAPIError.invalidResponse
        }
    }

    /// 从移动端作者链接读取发布者名称和投稿列表使用的数字用户 ID。
    private static func publisher(in scope: Element) throws -> ShenshiComicPublisher? {
        guard let link = try scope.select(".sub_r a[href*=\"albums-user-uid-\"]").first(),
              let match = try link.attr("href").firstMatch(
                  of: #/(?:^|/)albums-user-uid-([0-9]+)\.html(?:[?#].*)?$/#,
              )
        else {
            return nil
        }

        let name = try normalizedText(link.text())
        guard !name.isEmpty else {
            return nil
        }

        return ShenshiComicPublisher(id: String(match.1), name: name)
    }

    /// 从移动端分类链接读取与更新列表相同的数字 ID 和显示名称。
    private static func category(in scope: Element) throws -> ShenshiLatestCategory? {
        guard let link = try scope.select(".sub_r a[href*=\"albums-index-cate-\"]").first() else {
            return nil
        }

        return try ShenshiLatestCategoryHTMLParser.category(from: link)
    }

    /// 优先读取封面声明的完整标题，并在属性缺失时使用页面标题兜底。
    private static func comicTitle(from document: Document, coverImage: Element) throws -> String {
        let coverTitle = try normalizedText(coverImage.attr("title"))
        if !coverTitle.isEmpty {
            return coverTitle
        }

        let pageTitle = try normalizedText(document.title())
        guard let suffixRange = pageTitle.range(of: "-紳士漫畫") else {
            return pageTitle
        }

        return normalizedText(String(pageTitle[..<suffixRange.lowerBound]))
    }

    /// 从 `11P` 这类移动版文案中提取图片数量，无法识别时保持缺失。
    private static func pageCount(in scope: Element) throws -> Int? {
        let preferredText = try scope.select(".sub_r .date").first()?.text()
        let fallbackText = try scope.select(".sub_r .txtItme").text()

        // 主节点存在但不包含图片数量时，继续尝试备用节点。
        for case let value? in [preferredText, fallbackText] {
            guard let match = value.firstMatch(of: #/([0-9][0-9,]*)\s*[Pp](?:\b|$)/#) else {
                continue
            }

            return Int(String(match.1).replacingOccurrences(of: ",", with: ""))
        }
        return nil
    }

    /// 从当前漫画的评论分区标题或入口文案中读取评论总数；没有评论入口表示零评论。
    private static func commentCount(in document: Document, comicID: String) throws -> Int? {
        let commentLink = try document
            .select("a[href*=\"comment-index-aid-\"]")
            .first { link in
                try commentComicID(from: link.attr("href")) == comicID
            }
        guard let commentLink else {
            return 0
        }

        if let headerText = try commentSection(containing: commentLink)?
            .select(".dv-section-hd")
            .first()?
            .text(),
            let count = numericCount(in: headerText) {
            return count
        }

        let linkText = try normalizedText(commentLink.text()).convertedToSimplifiedChinese()
        if let count = numericCount(in: linkText) {
            return count
        }

        // 入口存在但文案格式未知时保持 nil；只有网页明确“抢沙发”时才返回零。
        return linkText.contains("抢沙发") ? 0 : nil
    }

    /// 从评论入口向上寻找对应的详情分区，不依赖内联样式或固定层级。
    private static func commentSection(containing link: Element) -> Element? {
        var element: Element? = link
        while let current = element {
            if current.hasClass("dv-section") {
                return current
            }
            element = current.parent()
        }
        return nil
    }

    /// 从绅士评论入口 URL 中提取数字漫画 ID。
    private static func commentComicID(from href: String) -> String? {
        guard let match = href.firstMatch(of: #/(?:^|/)comment-index-aid-([0-9]+)\.html(?:[?#].*)?$/#) else {
            return nil
        }

        return String(match.1)
    }

    /// 从评论分区的短文案中提取非负整数。
    private static func numericCount(in value: String) -> Int? {
        guard let match = value.firstMatch(of: #/([0-9][0-9,]*)/#) else {
            return nil
        }

        return Int(String(match.1).replacingOccurrences(of: ",", with: ""))
    }

    /// 读取网页简介；页面没有简介或只提供占位文案时返回空文本。
    private static func summary(in document: Document) throws -> String {
        guard let element = try document.select(".dv-desc-text").first() else {
            return ""
        }

        let value = try normalizedText(element.text())
        return value.convertedToSimplifiedChinese() == "暂无简介" ? "" : value
    }

    /// 按网页顺序读取非空且不重复的标签。
    private static func tags(in document: Document) throws -> [ShenshiComicTag] {
        var result: [ShenshiComicTag] = []

        for element in try document.select(".dv-tags a[href*=\"albums-index-tag-\"], a.dv-tag") {
            let name = try normalizedText(element.text())
            guard !name.isEmpty,
                  !result.contains(where: { $0.name == name }),
                  let navigationKey = try tagPath(from: element.attr("href")),
                  let tag = ShenshiComicTag(name: name, navigationKey: navigationKey)
            else {
                continue
            }

            result.append(tag)
        }
        return result
    }

    /// 从相对或完整标签 URL 中保留网页已编码的请求路径。
    private static func tagPath(from href: String) -> String? {
        guard let match = href.firstMatch(of: #/(?:^|/)(albums-index-tag-[^/?#]+\.html)(?:[?#].*)?$/#) else {
            return nil
        }

        return String(match.1)
    }

    /// 跳过单个坏推荐卡片，按网页顺序保留有效推荐项；静态列表不去重。
    private static func relatedComics(in document: Document) throws -> [ComicListItem] {
        var result: [ComicListItem] = []
        for element in try document.select(".dv-rec-grid a[href*=\"photos-index-aid-\"]") {
            if let item = try relatedComic(from: element) {
                result.append(item)
            }
        }
        return result
    }

    /// 从一个热门推荐链接读取稳定身份、标题和封面。
    private static func relatedComic(from element: Element) throws -> ComicListItem? {
        guard let comicID = try ShenshiComicListItemHTMLParser.comicID(from: element.attr("href")) else {
            return nil
        }

        let imageCandidates = try Array(element.select("img[src]"))
        guard let image = try imageCandidates.first(where: { try !$0.attr("src").isEmpty }) else {
            return nil
        }

        let imageLocator = try image.attr("src")
        var title = try normalizedText(element.select(".dv-rec-title").first()?.text() ?? "")
        if title.isEmpty {
            title = try normalizedText(image.attr("alt"))
        }
        guard !title.isEmpty else {
            return nil
        }

        return ComicListItem(
            identity: ComicIdentity(sourceID: .shenshi, comicID: comicID),
            title: title,
            subtitle: nil,
            cover: .remote(
                ComicImageReference(
                    sourceID: .shenshi,
                    ownerID: comicID,
                    locator: imageLocator,
                    purpose: .cover,
                    variant: nil,
                ),
            ),
        )
    }

    /// 合并 HTML 排版空白，不修改文字中的实际内容。
    private static func normalizedText(_ value: String) -> String {
        value.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}

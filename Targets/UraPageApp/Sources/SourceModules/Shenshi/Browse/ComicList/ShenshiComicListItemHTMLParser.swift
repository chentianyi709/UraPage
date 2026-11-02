import Foundation
import SwiftSoup

/// 将绅士网页中的一个漫画卡片解析为跨页面共用的列表展示值。
///
/// 解析对网页结构变化保持容错：标题、附加信息节点 class 改名时按候选顺序回退，
/// 但身份（详情链接中的数字 ID）缺失时直接跳过该卡片。
enum ShenshiComicListItemHTMLParser {
    /// 从移动端普通列表容器中读取所有可用漫画卡片。
    static func items(in document: Document) throws -> [ComicListItem] {
        guard let listContainer = try comicListContainer(in: document) else {
            throw ShenshiAPIError.invalidResponse
        }

        let cardElements = listContainer.children().filter { $0.tagName() == "li" }
        let items = try cardElements.compactMap { try item(from: $0) }

        // 有卡片却没有一个能解析出身份，说明页面结构与预期不符。
        guard cardElements.isEmpty || !items.isEmpty else {
            throw ShenshiAPIError.invalidResponse
        }

        return items
    }

    /// 从一个完整卡片中读取详情标识、标题、附加信息和封面地址。
    static func item(from element: Element) throws -> ComicListItem? {
        // 详情链接是卡片身份的来源；没有它就无法构造稳定 identity。
        guard let detailLink = try element.select("a[href*=\"photos-index-aid-\"]").first() else {
            return nil
        }

        // 封面可能在详情链接内或卡片其它位置，按顺序取第一张非空图片。
        let imageCandidates = try Array(detailLink.select("img[src]"))
            + Array(element.select("img[src]"))
        guard let image = try imageCandidates.first(where: { try !$0.attr("src").isEmpty }) else {
            return nil
        }
        guard let comicID = try comicID(from: detailLink.attr("href")) else {
            return nil
        }

        let title = try comicTitle(from: element, image: image)
        guard !title.isEmpty else {
            return nil
        }

        return try ComicListItem(
            identity: ComicIdentity(sourceID: .shenshi, comicID: comicID),
            title: title,
            subtitle: makeSubtitle(from: metadataText(in: element)),
            cover: .remote(
                ComicImageReference(
                    sourceID: .shenshi,
                    ownerID: comicID,
                    locator: image.attr("src"),
                    purpose: .cover,
                    variant: nil,
                ),
            ),
        )
    }

    /// 优先使用当前稳定标题节点，并在 class 改名时回退到其它非空链接或图片 alt。
    private static func comicTitle(from element: Element, image: Element) throws -> String {
        if let title = try element.select(".title a").first()?.text(), !title.isEmpty {
            return title
        }
        if let title = try element.select("a.txtA").first()?.text(), !title.isEmpty {
            return title
        }
        for link in try element.select("a") {
            let title = try link.text()
            if !title.isEmpty {
                return title
            }
        }
        return try image.attr("alt")
    }

    /// 优先读取当前稳定信息节点，并在 class 改名时寻找仍包含数量或日期的短文本。
    private static func metadataText(in element: Element) throws -> String {
        if let value = try element.select(".info_col").first()?.text(), !value.isEmpty {
            return value
        }
        if let value = try element.select(".info").first()?.text(), !value.isEmpty {
            return value
        }
        for candidate in try element.select("span, p, div") {
            let value = try candidate.text()
            if value.contains("張")
                || value.contains("张")
                || value.firstMatch(of: #/[0-9]{4}\s*[-/.年]\s*[0-9]{1,2}/#) != nil {
                return value
            }
        }
        return ""
    }

    /// 从附加信息中分别提取图片数量和日期，避免依赖字段顺序、标点或固定文案。
    private static func makeSubtitle(from value: String) -> String {
        var parts: [String] = []

        if let match = value.firstMatch(of: #/([0-9][0-9,]*)\s*[張张](?:圖片|图片)?/#) {
            parts.append("\(match.1)张")
        }
        if let match = value
            .firstMatch(of: #/([0-9]{4})\s*[-/.年]\s*([0-9]{1,2})\s*[-/.月]\s*([0-9]{1,2})\s*日?/#),
            let month = Int(match.2),
            let day = Int(match.3),
            (1 ... 12).contains(month),
            (1 ... 31).contains(day) {
            parts.append("\(match.1)-\(String(format: "%02d", month))-\(String(format: "%02d", day))")
        }

        if !parts.isEmpty {
            return parts.joined(separator: " · ")
        }

        // 未识别的新格式仍保留原始信息，避免网页微调后副标题静默消失。
        return value.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// 从相对或完整详情 URL 中提取服务端数字漫画标识。
    static func comicID(from href: String) -> String? {
        guard let match = href.firstMatch(of: #/(?:^|/)photos-index-aid-([0-9]+)\.html(?:[?#].*)?$/#) else {
            return nil
        }

        return String(match.1)
    }

    /// 优先使用移动端稳定容器，再寻找包含漫画详情链接的列表。
    private static func comicListContainer(in document: Document) throws -> Element? {
        if let container = try document.select("#classify_container").first() {
            return container
        }
        for list in try document.select("ul.col_2, ul") {
            if try !list.select("a[href*=\"photos-index-aid-\"]").isEmpty {
                return list
            }
        }
        return nil
    }
}

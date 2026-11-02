import Foundation
import SwiftSoup

/// 从绅士漫画地址发布页中提取业务 Base URL。
enum ShenshiHostHTMLParser {
    /// 发布页用于标记业务地址的稳定可见文案。
    private static let latestAddressMarker = "紳士漫畫最新地址"

    /// 提取页面按优先级排列的业务 Base URL。
    static func baseURLs(from html: String) throws -> [URL] {
        let document: Document
        do {
            document = try SwiftSoup.parse(html)
        } catch {
            throw ShenshiHostResolutionError.invalidBootstrapHTML
        }

        var baseURLs: [URL] = []
        do {
            for link in try document.select("a[href]") {
                // 发布页还包含邮箱、备用网址和浏览器下载地址，只读取带“最新地址”标记的链接。
                guard let container = link.parent(),
                      try container.text().contains(latestAddressMarker),
                      let baseURL = try URL(string: link.attr("href"))
                else {
                    continue
                }

                baseURLs.append(baseURL)
            }
        } catch let error as ShenshiHostResolutionError {
            throw error
        } catch {
            throw ShenshiHostResolutionError.invalidBootstrapHTML
        }

        guard !baseURLs.isEmpty else {
            throw ShenshiHostResolutionError.emptyHostList
        }

        return baseURLs
    }
}

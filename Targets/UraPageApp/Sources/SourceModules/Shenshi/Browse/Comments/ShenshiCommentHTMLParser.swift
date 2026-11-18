import Foundation
import SwiftSoup

/// 把绅士移动端评论页解析为公共展示值。
///
/// 只取界面要展示的四项与回复关系；点赞、楼层等来源私有字段不进入模型。
enum ShenshiCommentHTMLParser {
    /// 解析服务端直接输出的评论、内嵌回复与评论总数。
    static func page(from html: String) throws -> ComicCommentPage {
        do {
            let document = try SwiftSoup.parse(html)
            guard let list = try document.select("#plList").first() else {
                AppLogger.error("移动版 HTML 缺少评论列表容器", category: "Shenshi.Comments")
                throw ComicSourceError.invalidResponse
            }

            let elements = try list.select(".plItem[data-id]")
            var comments: [ComicComment] = []
            var commentIDs = Set<String>()

            // 单条评论结构异常时跳过该条，不让局部内容影响整页。
            for element in elements {
                do {
                    guard let comment = try comment(from: element),
                          commentIDs.insert(comment.id).inserted
                    else {
                        continue
                    }

                    comments.append(comment)
                } catch {
                    AppLogger.warning(
                        "跳过无法解析的评论，errorType=\(String(reflecting: type(of: error)))",
                        category: "Shenshi.Comments",
                    )
                }
            }

            // 页面声明了评论节点却全部无法转换时，说明关键结构已经变化。
            guard elements.isEmpty || !comments.isEmpty else {
                throw ComicSourceError.invalidResponse
            }

            return try ComicCommentPage(
                comments: comments,
                total: max(totalCount(in: document) ?? 0, comments.count),
                // 评论页一次输出全部评论，没有下一页；不再让公共层按 total 反推。
                hasMore: false,
            )
        } catch let error as ComicSourceError {
            throw error
        } catch {
            AppLogger.error(
                "评论 HTML 解析失败，errorType=\(String(reflecting: type(of: error)))",
                category: "Shenshi.Comments",
            )
            throw ComicSourceError.invalidResponse
        }
    }

    /// 从一个顶级评论节点读取用户、正文、时间、头像和内嵌回复。
    private static func comment(from element: Element) throws -> ComicComment? {
        let id = try normalizedText(element.attr("data-id"))
        guard !id.isEmpty,
              let body = try element.select(".plBody").first()
        else {
            return nil
        }

        let nickname = try normalizedText(
            body.children().first(where: { $0.hasClass("plName") })?.text() ?? "",
        )
        let contentElement = body.children().first(where: { $0.hasClass("plText") })
        let meta = body.children().first(where: { $0.hasClass("plMeta") })

        return try ComicComment(
            id: id,
            nickname: nickname,
            avatar: avatarReference(from: element.select(".plAv[src]").first()),
            dateText: shortText(from: meta?.select(".plTime").first()),
            content: commentContent(from: contentElement),
            replies: replies(in: body),
        )
    }

    /// 读取当前评论下直接出现在首屏 HTML 里的回复。
    private static func replies(in body: Element) throws -> [ComicComment] {
        var replies: [ComicComment] = []
        var replyIDs = Set<String>()

        for element in try body.select(".plReplies .plRe[data-id]") {
            do {
                guard let reply = try reply(from: element),
                      replyIDs.insert(reply.id).inserted
                else {
                    continue
                }

                replies.append(reply)
            } catch {
                AppLogger.warning(
                    "跳过无法解析的评论回复，errorType=\(String(reflecting: type(of: error)))",
                    category: "Shenshi.Comments",
                )
            }
        }

        return replies
    }

    /// 从一个回复节点读取回复人、被回复人、正文和时间。
    private static func reply(from element: Element) throws -> ComicComment? {
        let id = try normalizedText(element.attr("data-id"))
        guard !id.isEmpty else {
            return nil
        }

        let nickname = try normalizedText(element.select(".plName").first()?.text() ?? "")
        // `em` 是「回复 某某：」的提及；清洗规则在 `CommentReplyTarget`，正文里不再重复这段。
        let target = try CommentReplyTarget.name(from: element.select("em").first()?.text() ?? "")

        // 复制节点后摘掉名称／时间／提及，正文按顶级评论同一套规则提取：
        // `ownText()` 会丢掉 `<br>`、链接和子元素里的文字，长回复只剩第一段。
        guard let body = element.copy() as? Element else {
            return nil
        }

        try body.select(".plName, .plMeta, em").remove()
        let content = try replyContent(from: commentContent(from: body))

        return try ComicComment(
            id: id,
            nickname: nickname,
            replyTargetName: target,
            dateText: shortText(from: element.select(".plMeta .plTime").first()),
            content: content,
        )
    }

    /// 保留评论中的换行，其余标签去掉并解码实体。
    private static func commentContent(from element: Element?) throws -> String {
        guard let element else {
            return ""
        }

        let html = try element.html().replacingOccurrences(
            of: #"(?i)<br\s*/?>"#,
            with: "\n",
            options: .regularExpression,
        )
        var lines = try html
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { fragment in
                try SwiftSoup.parseBodyFragment(String(fragment))
                    .text()
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }

        while lines.first?.isEmpty == true {
            lines.removeFirst()
        }
        while lines.last?.isEmpty == true {
            lines.removeLast()
        }
        return lines.joined(separator: "\n")
    }

    /// 去掉 HTML 排版使用的「回复：」前缀，只保留正文。
    private static func replyContent(from ownText: String) -> String {
        ownText
            .replacingOccurrences(
                of: #"^(?:回复|回覆)\s*[:：]?\s*"#,
                with: "",
                options: .regularExpression,
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 把头像路径保存为由当前绅士 Host 解析的图片引用；默认头像按无头像处理。
    private static func avatarReference(from element: Element?) throws -> ComicImageReference? {
        guard let element else {
            return nil
        }

        let locator = try element.attr("src")
        guard !locator.isEmpty,
              !locator.localizedCaseInsensitiveContains("no_avatar")
        else {
            return nil
        }

        return ComicImageReference(
            sourceID: .shenshi,
            // 头像没有所属业务对象，按图片引用约定用空串，同一张图共用缓存。
            ownerID: "",
            locator: locator,
            purpose: .avatar,
            variant: nil,
        )
    }

    /// 从评论标题中提取服务端声明的评论总数。
    private static func totalCount(in document: Document) throws -> Int? {
        for element in try document.select(".plSecT, .BarTit") {
            guard let match = try element.text().firstMatch(of: #/([0-9][0-9,]*)/#) else {
                continue
            }

            return Int(String(match.1).replacingOccurrences(of: ",", with: ""))
        }

        return nil
    }

    /// 读取可选短文本并统一排版空白，保留页面原文。
    private static func shortText(from element: Element?) throws -> String {
        try normalizedText(element?.text() ?? "")
    }

    /// 合并 HTML 排版空白，不改变正文中的显式换行。
    private static func normalizedText(_ value: String) -> String {
        value.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}

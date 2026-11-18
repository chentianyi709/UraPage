import Foundation

/// 把禁漫评论分页转换为公共展示值。
///
/// ID 为空或重复的条目直接跳过：评论 ID 是回复展开与列表身份的依据，坏值不能进入列表。
func makeJMComicCommentPage(from response: JMComicCommentsResponseDTO) -> ComicCommentPage {
    var commentIDs = Set<String>()
    // 一页只建一次解析器：一页十几条没必要每条都分配一个 DateFormatter。
    let dateParser = makeJMComicCommentDateParser()

    let comments = response.comments.compactMap { comment -> ComicComment? in
        guard !comment.id.isEmpty, commentIDs.insert(comment.id).inserted else {
            return nil
        }

        return makeJMComicComment(from: comment, dateParser: dateParser)
    }

    return ComicCommentPage(
        comments: comments,
        total: response.total,
        // `/forum` 只返回 `list` 与 `total`，没有页码与总页数，来源给不出「是否末页」。
        // 曾经写成「本页条数 < total」，但每页条数恒小于总数，末页照样判真，会多请求一页。
        // 交给公共层用累计条数折算。
        hasMore: nil,
    )
}

/// 组装一条顶级评论，并过滤 ID 为空或重复的回复。
private func makeJMComicComment(
    from comment: JMComicCommentDTO,
    dateParser: DateFormatter,
) -> ComicComment {
    var replyIDs = Set<String>()
    let replies = comment.replies.compactMap { reply -> ComicComment? in
        guard !reply.id.isEmpty, replyIDs.insert(reply.id).inserted else {
            return nil
        }

        return ComicComment(
            id: reply.id,
            nickname: reply.nickname.trimmingCharacters(in: .whitespacesAndNewlines),
            avatar: makeJMComicCommentAvatar(photo: reply.photo),
            dateText: makeJMComicCommentDateText(reply.addtime, parser: dateParser),
            content: makeJMComicCommentContent(reply.content),
        )
    }

    return ComicComment(
        id: comment.id,
        nickname: comment.nickname.trimmingCharacters(in: .whitespacesAndNewlines),
        avatar: makeJMComicCommentAvatar(photo: comment.photo),
        dateText: makeJMComicCommentDateText(comment.addtime, parser: dateParser),
        content: makeJMComicCommentContent(comment.content),
        replies: replies,
    )
}

/// 评论头像：接口只给文件名，由禁漫图片服务补全目录与当前图片 Host。
///
/// 头像没有所属业务对象，`ownerID` 按图片引用约定用空串——同一个文件在不同评论里
/// 命中同一份缓存；用评论 ID 会让每条评论各存一份相同头像。
private func makeJMComicCommentAvatar(photo: String) -> ComicImageReference? {
    let photo = photo.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !photo.isEmpty else {
        return nil
    }

    return ComicImageReference(
        sourceID: .jm,
        ownerID: "",
        locator: photo,
        purpose: .avatar,
        variant: nil,
    )
}

/// 禁漫日期是 `MMM dd, yyyy`；按页共享同一个解析器。
private func makeJMComicCommentDateParser() -> DateFormatter {
    let parser = DateFormatter()
    parser.locale = Locale(identifier: "en_US_POSIX")
    parser.dateFormat = "MMM dd, yyyy"
    return parser
}

/// 把禁漫的英文日期转换成统一的相对文案；解析失败保留原文。
private func makeJMComicCommentDateText(_ value: String, parser: DateFormatter) -> String {
    let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !value.isEmpty else {
        return ""
    }
    guard let date = parser.date(from: value) else {
        return value
    }

    return CommentDateText.formatted(date)
}

/// 去掉 HTML 标签、把 `<br>` 还原成换行、解码常见实体，保留正文原有分段。
private func makeJMComicCommentContent(_ value: String) -> String {
    value
        .replacing(/(?i)<br\s*\/?>/, with: "\n")
        .replacing(/<[^>]+>/, with: "")
        .replacingOccurrences(of: "&nbsp;", with: " ")
        .replacingOccurrences(of: "&lt;", with: "<")
        .replacingOccurrences(of: "&gt;", with: ">")
        .replacingOccurrences(of: "&quot;", with: "\"")
        .replacingOccurrences(of: "&#39;", with: "'")
        // `&amp;` 必须最后解，否则 `&amp;lt;` 会被二次解码成 `<`。
        .replacingOccurrences(of: "&amp;", with: "&")
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

import Foundation

/// 把哔咔评论分页转换为公共展示值。
///
/// 评论 ID 是子评论接口的唯一入参，为空或重复的条目直接跳过。
func makeBikaComicCommentPage(from response: BikaComicCommentsPageDTO) -> ComicCommentPage {
    // Formatter 只在单页映射边界创建一次，避免每条评论重复分配。
    let fractionalParser = makeBikaCommentDateParser(includesFractionalSeconds: true)
    let plainParser = makeBikaCommentDateParser(includesFractionalSeconds: false)
    var commentIDs = Set<String>()

    let comments = response.docs.compactMap { comment -> ComicComment? in
        let requestID = comment.requestID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !requestID.isEmpty, commentIDs.insert(requestID).inserted else {
            return nil
        }

        return ComicComment(
            id: requestID,
            nickname: comment.user?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            avatar: makeBikaCommentAvatar(user: comment.user),
            dateText: makeBikaCommentDateText(
                comment.createdAt,
                fractionalParser: fractionalParser,
                plainParser: plainParser,
            ),
            content: comment.content.trimmingCharacters(in: .whitespacesAndNewlines),
            replyCount: max(comment.totalComments ?? 0, comment.commentsCount),
        )
    }

    return ComicCommentPage(
        comments: comments,
        total: response.total,
        // 有总页数就按页码判断；没有时交给公共层按累计条数折算。
        hasMore: response.pages > 0 ? response.page < response.pages : nil,
    )
}

/// 头像按用户 ID 做缓存身份：同一用户的头像在每条评论下共用一份缓存。
///
/// 拿不到用户 ID 时按图片引用约定用空串，而不是退回评论 ID——
/// 评论 ID 每条都不同，会把同一张图重复下载很多份。
private func makeBikaCommentAvatar(
    user: BikaComicCommentUserDTO?,
) -> ComicImageReference? {
    guard let avatar = user?.avatar else {
        return nil
    }

    let userID = user?.id.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return BikaImageReferenceFactory.make(
        ownerID: userID,
        fileServer: avatar.fileServer,
        path: avatar.path,
        purpose: .avatar,
    )
}

/// 把 ISO 8601 时间转换成统一的相对文案；解析失败保留清理后的原文。
private func makeBikaCommentDateText(
    _ value: String,
    fractionalParser: ISO8601DateFormatter,
    plainParser: ISO8601DateFormatter,
) -> String {
    let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !value.isEmpty else {
        return ""
    }
    guard let date = fractionalParser.date(from: value) ?? plainParser.date(from: value) else {
        return value
    }

    return CommentDateText.formatted(date)
}

/// 单页映射专用解析器：不在并发请求之间共享可变 Formatter。
private func makeBikaCommentDateParser(includesFractionalSeconds: Bool) -> ISO8601DateFormatter {
    let parser = ISO8601DateFormatter()
    parser.formatOptions = includesFractionalSeconds
        ? [.withInternetDateTime, .withFractionalSeconds]
        : [.withInternetDateTime]
    return parser
}

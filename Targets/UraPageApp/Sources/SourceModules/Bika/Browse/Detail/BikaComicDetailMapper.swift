import Foundation

/// 将哔咔详情和完整章节列表转换为页面公开模型。
func makeBikaComicDetail(
    from comic: BikaComicDetailDTO,
    chapterDTOs: [BikaEpisodeDTO],
    requestedIdentity: ComicIdentity,
) throws -> BikaComicDetail {
    // 主详情必须仍然对应请求 identity，避免把服务端错配内容提交到当前 route。
    guard comic.id == requestedIdentity.comicID else {
        throw BikaAPIError.invalidResponse
    }

    // 哔咔 eps 按「最新在前」返回，这里统一按 order 升序输出阅读顺序（第 1 章在前）：
    // Reader 章节列表、开始阅读与选章弹窗都依赖这个顺序。章节来自多页合并，按 order 去重保证身份唯一。
    var orders = Set<Int>()
    let chapters = chapterDTOs
        .sorted { $0.order < $1.order }
        .compactMap { chapter -> BikaComicChapter? in
            guard chapter.order >= 1, orders.insert(chapter.order).inserted else {
                return nil
            }

            return BikaComicChapter(
                comicIdentity: requestedIdentity,
                title: chapter.title,
                order: chapter.order,
            )
        }

    var contributors: [BikaComicContributor] = []
    if let authorName = nonemptyBikaDetailText(comic.author) {
        contributors.append(.author(name: authorName))
    }
    if let chineseTeamName = nonemptyBikaDetailText(comic.chineseTeam) {
        contributors.append(.chineseTeam(name: chineseTeamName))
    }
    if let uploaderName = nonemptyBikaDetailText(comic.creator.name) {
        contributors.append(.uploader(id: comic.creator.id, name: uploaderName))
    }

    // 详情封面是响应级必需字段：locator 无效说明响应用不了，不降级为无封面。
    guard let cover = BikaImageReferenceFactory.make(
        ownerID: comic.id,
        fileServer: comic.thumb.fileServer,
        path: comic.thumb.path,
        purpose: .cover,
        fixedQuality: .original,
    ) else {
        throw BikaAPIError.invalidResponse
    }

    return BikaComicDetail(
        identity: requestedIdentity,
        title: comic.title,
        summary: comic.summary,
        tags: comic.tags,
        cover: .remote(cover),
        contributors: contributors,
        categories: comic.categories.compactMap(nonemptyBikaDetailText).map(BikaComicCategory.init(title:)),
        pageCount: comic.pagesCount,
        viewCount: comic.totalViews,
        likeCount: comic.totalLikes,
        isLiked: comic.isLiked,
        isFinished: comic.finished,
        updatedDateText: makeBikaUpdatedDateText(comic.updatedAt),
        chapters: chapters,
    )
}

/// 把详情接口的 ISO8601 更新时间（如 `2026-11-08T18:07:12.588Z`）转为与禁漫一致的本地日期文本。
private func makeBikaUpdatedDateText(_ updatedAt: String?) -> String? {
    guard let updatedAt = nonemptyBikaDetailText(updatedAt),
          let date = bikaISO8601Date(from: updatedAt)
    else {
        return nil
    }

    let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
    guard let year = components.year, let month = components.month, let day = components.day else {
        return nil
    }

    return String(format: "%04d-%02d-%02d", year, month, day)
}

/// 解析哔咔返回的 ISO8601 时间；毫秒可缺席，两种形式都接受。
private func bikaISO8601Date(from text: String) -> Date? {
    if let date = try? Date(text, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)) {
        return date
    }

    return try? Date(text, strategy: .iso8601)
}

/// 把接口空文本收敛为详情页可选字段。
private func nonemptyBikaDetailText(_ value: String?) -> String? {
    guard let value else {
        return nil
    }

    let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmedValue.isEmpty ? nil : trimmedValue
}

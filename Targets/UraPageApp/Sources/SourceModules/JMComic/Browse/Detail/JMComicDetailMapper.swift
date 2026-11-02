import Foundation

/// 将禁漫详情 DTO 转换为页面可以直接使用的来源展示模型。
func makeJMComicDetail(from detail: JMComicDetailDTO) throws -> JMComicDetail {
    guard !detail.id.isEmpty else {
        throw JMComicAPIError.invalidResponse
    }

    let identity = ComicIdentity(sourceID: .jm, comicID: detail.id)
    let chapters = makeJMChapters(from: detail.series, comicIdentity: identity)

    // 相关推荐是单次响应的静态列表，不做漫画去重；坏项跳过。
    let relatedComics = detail.relatedList.compactMap {
        makeJMRelatedComic(from: $0, updatedAt: detail.addtime)
    }

    return JMComicDetail(
        identity: identity,
        title: detail.name,
        authors: detail.author,
        viewCount: detail.totalViews,
        likeCount: detail.likes,
        isLiked: detail.liked,
        commentCount: detail.commentTotal,
        publishedDateText: makeJMPublishedDateText(timestamp: detail.addtime),
        summary: detail.description,
        tags: detail.tags,
        pageCount: detail.totalPhotos,
        chapters: chapters,
        cover: .remote(makeJMCoverReference(comicID: detail.id, image: "", updatedAt: detail.addtime)),
        relatedComics: relatedComics,
    )
}

/// 将有效章节映射为完整 identity，并按服务端 `sort` 稳定排列。
///
/// 章节来自单次响应，不在来源层去重；只保留按 `sort` 的稳定排序。
private func makeJMChapters(
    from chapters: [JMComicChapterDTO],
    comicIdentity: ComicIdentity,
) -> [JMComicChapter] {
    chapters.enumerated()
        .compactMap { responseIndex, chapter -> JMComicChapterCandidate? in
            guard !chapter.id.isEmpty else {
                return nil
            }

            let name = chapter.name.trimmingCharacters(in: .whitespacesAndNewlines)
            return JMComicChapterCandidate(
                responseIndex: responseIndex,
                sort: chapter.sort,
                chapter: JMComicChapter(
                    identity: ChapterIdentity(comic: comicIdentity, chapterID: chapter.id),
                    title: name.isEmpty ? "第 \(chapter.sort) 话" : name,
                ),
            )
        }
        .sorted { lhs, rhs in
            lhs.sort == rhs.sort ? lhs.responseIndex < rhs.responseIndex : lhs.sort < rhs.sort
        }
        .map(\.chapter)
}

/// 保留章节排序值和响应位置，避免同序号章节发生不稳定重排。
private struct JMComicChapterCandidate {
    let responseIndex: Int
    let sort: Int
    let chapter: JMComicChapter
}

/// 跳过缺少 ID 的相关推荐，并复用普通漫画列表展示值。
private func makeJMRelatedComic(from comic: JMComicRelatedDTO, updatedAt: Int) -> ComicListItem? {
    guard !comic.id.isEmpty else {
        return nil
    }

    return ComicListItem(
        identity: ComicIdentity(sourceID: .jm, comicID: comic.id),
        title: comic.name,
        subtitle: comic.author,
        cover: .remote(makeJMCoverReference(comicID: comic.id, image: comic.image, updatedAt: updatedAt)),
    )
}

/// 按详情页格式把有效的服务端秒级时间戳转换为本地日期。
private func makeJMPublishedDateText(timestamp: Int) -> String? {
    guard timestamp > 0 else {
        return nil
    }

    let components = Calendar.current.dateComponents(
        [.year, .month, .day],
        from: Date(timeIntervalSince1970: TimeInterval(timestamp)),
    )
    guard let year = components.year, let month = components.month, let day = components.day else {
        return nil
    }

    return String(format: "%04d-%02d-%02d", year, month, day)
}

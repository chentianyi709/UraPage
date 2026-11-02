import Foundation

/// 保存一张禁漫页的内部请求和解扰参数。
struct JMComicPageDescriptor: SourcePageDescriptor {
    let identity: PageIdentity
    let url: URL
    let aid: String
    let scrambleID: String
}

/// 将公开章节值与仅在禁漫源内使用的页面描述分开。
struct JMComicResolvedChapterContent: Sendable {
    let content: SourceChapterContent
    let pageDescriptors: [JMComicPageDescriptor]
}

/// 把 `/comic_read` DTO 转换为公共章节值和禁漫内部页面描述。
func makeJMResolvedChapterContent(
    from response: JMComicChapterContentDTO,
    identity: ChapterIdentity,
    imageHost: URL,
) throws -> JMComicResolvedChapterContent {
    // 按服务端页序号稳定排序，同序号保持响应先后。
    let sortedImages = response.images.enumerated().sorted { lhs, rhs in
        lhs.element.page == rhs.element.page ? lhs.offset < rhs.offset : lhs.element.page < rhs.element.page
    }

    var seenIdentities = Set<PageIdentity>()
    var pages: [ComicPage] = []
    var descriptors: [JMComicPageDescriptor] = []

    for (_, image) in sortedImages {
        let pageIdentity = PageIdentity(chapter: identity, pageID: String(image.page))

        // 地址无效的条目不占用 identity，让后续同页码的有效记录仍可参与阅读。
        guard let imageURL = resolvedJMPageURL(from: image.image, imageHost: imageHost) else {
            continue
        }

        // 同一页序号只保留首个有效项，保证 Reader 页面身份唯一。
        guard seenIdentities.insert(pageIdentity).inserted else {
            continue
        }

        pages.append(ComicPage(identity: pageIdentity, index: pages.count))
        descriptors.append(
            JMComicPageDescriptor(
                identity: pageIdentity,
                url: imageURL,
                aid: response.id,
                scrambleID: response.scrambleID,
            ),
        )
    }

    return JMComicResolvedChapterContent(
        content: SourceChapterContent(identity: identity, title: response.name, pages: pages),
        pageDescriptors: descriptors,
    )
}

/// 直接使用完整地址，或使用当前 Setting 的图片 Host 解析相对定位值。
private func resolvedJMPageURL(from value: String, imageHost: URL) -> URL? {
    guard !value.isEmpty else {
        return nil
    }

    if value.hasPrefix("//") {
        return URL(string: "https:\(value)")
    }
    if let absoluteURL = URL(string: value), absoluteURL.scheme != nil, absoluteURL.host != nil {
        return absoluteURL
    }
    return URL(string: value, relativeTo: imageHost)?.absoluteURL
}

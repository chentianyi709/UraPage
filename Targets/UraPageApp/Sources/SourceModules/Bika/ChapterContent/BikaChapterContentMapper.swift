import Foundation

/// 保存一张 Bika Reader 页面在 Source Target 内使用的请求信息。
struct BikaPageDescriptor: SourcePageDescriptor {
    let identity: PageIdentity
    let url: URL
}

/// 将公共章节值与来源内部页面请求描述分开。
struct BikaResolvedChapterContent: Sendable {
    let content: SourceChapterContent
    let pageDescriptors: [BikaPageDescriptor]
    let batchSize: Int
}

/// 按服务端分页顺序创建固定原画的稳定页面身份。
func makeBikaResolvedChapterContent(
    from response: BikaChapterPagesDTO,
    identity: ChapterIdentity,
) throws -> BikaResolvedChapterContent {
    guard response.total >= 0, response.limit > 0, response.page >= 1,
          response.docs.count <= response.limit else { throw BikaAPIError.invalidResponse }

    let pageDTOs = response.docs
    let offset = (response.page - 1) * response.limit
    var remoteIDs = Set<String>()
    var pages: [ComicPage] = []
    var descriptors: [BikaPageDescriptor] = []

    for (sourceIndex, dto) in pageDTOs.enumerated() {
        // 空 ID 无法建立稳定页面 identity；坏单项不应影响同章其它页面。
        guard !dto.id.isEmpty else {
            continue
        }

        // locator 只影响当前页请求；无法生成合法 URL 时继续保留同章其它页面。
        guard let imageURL = BikaImageReferenceFactory.imageURL(
            fileServer: dto.media.fileServer,
            path: dto.media.path,
        ) else {
            continue
        }

        // 仅让完整有效的条目占用远端 ID，避免坏首项挡住后续同 ID 的有效页面。
        guard remoteIDs.insert(dto.id).inserted else {
            continue
        }

        let pageIdentity = PageIdentity(chapter: identity, pageID: dto.id)
        pages.append(ComicPage(identity: pageIdentity, index: offset + sourceIndex))
        descriptors.append(BikaPageDescriptor(identity: pageIdentity, url: imageURL))
    }

    return BikaResolvedChapterContent(
        content: SourceChapterContent(
            identity: identity,
            title: "",
            pages: pages,
            totalPageCount: response.total,
        ),
        pageDescriptors: descriptors,
        batchSize: response.limit,
    )
}

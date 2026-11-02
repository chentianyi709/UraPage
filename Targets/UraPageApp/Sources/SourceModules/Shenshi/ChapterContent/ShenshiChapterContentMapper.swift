import Foundation

/// 保存一张绅士 Reader 页面在 Source Target 内使用的请求信息。
struct ShenshiPageDescriptor: SourcePageDescriptor {
    let identity: PageIdentity
    let url: URL
    let userAgent: String
    let referer: URL
}

/// 将公共章节值与来源内部页面请求信息分开。
struct ShenshiResolvedChapterContent: Sendable {
    let content: SourceChapterContent
    let pageDescriptors: [ShenshiPageDescriptor]
}

/// 按脚本数组顺序创建稳定页面身份，并保留有效图片请求。
func makeShenshiResolvedChapterContent(
    from pageURLStrings: [String],
    identity: ChapterIdentity,
    baseURL: URL,
    userAgent: String,
) throws -> ShenshiResolvedChapterContent {
    var pages: [ComicPage] = []
    var descriptors: [ShenshiPageDescriptor] = []

    for (sourceIndex, value) in pageURLStrings.enumerated() {
        guard let imageURL = resolvedShenshiReaderPageURL(from: value, relativeTo: baseURL) else {
            continue
        }

        // 脚本没有独立页面 ID，使用服务端数组中的原始位置作为稳定页身份。
        let pageIdentity = PageIdentity(chapter: identity, pageID: String(sourceIndex + 1))
        pages.append(ComicPage(identity: pageIdentity, index: pages.count))
        descriptors.append(
            ShenshiPageDescriptor(
                identity: pageIdentity,
                url: imageURL,
                userAgent: userAgent,
                referer: baseURL,
            ),
        )
    }

    // 单个坏地址只跳过该页；非空数组全部失效才说明响应无法使用。
    guard pageURLStrings.isEmpty || !pages.isEmpty else {
        throw ShenshiAPIError.invalidResponse
    }

    return ShenshiResolvedChapterContent(
        content: SourceChapterContent(identity: identity, title: "", pages: pages),
        pageDescriptors: descriptors,
    )
}

/// 解析完整、协议相对或相对图片地址，并把网页返回的 HTTP 统一升级为 HTTPS。
private func resolvedShenshiReaderPageURL(from value: String, relativeTo baseURL: URL) -> URL? {
    guard !value.isEmpty,
          let resolvedURL = URL(string: value, relativeTo: baseURL)?.absoluteURL,
          var components = URLComponents(url: resolvedURL, resolvingAgainstBaseURL: false)
    else {
        return nil
    }

    if components.scheme?.lowercased() == "http" {
        components.scheme = "https"
    }
    guard components.scheme?.lowercased() == "https", components.host != nil else {
        return nil
    }

    return components.url
}

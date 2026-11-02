import Alamofire
import Foundation

/// 实现 Bika 在线 Reader 与后续 Download 共用的稳定章节入口。
actor BikaChapterContentService: SourceChapterContentService {
    nonisolated let sourceID = ComicSourceID.bika

    private let client: BikaSourceClient

    /// Reader 与作品下载共用无 API 拦截器、无 URLCache 的章节页 Session。
    private let pageSession = BikaChapterContentService.makePageTransferSession()

    /// 使用业务 Client 创建始终请求原画的章节入口；图片线路偏好由 Client 持有。
    init(client: BikaSourceClient) {
        self.client = client
    }

    /// 创建阅读页传输 Session，并隔离图片 CDN 的 Cookie。
    private static func makePageTransferSession() -> Session {
        let configuration = SourceConfiguration.Session.pageTransferConfiguration()
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        return Session(configuration: configuration)
    }

    /// 打开章节，并将原画页面请求描述绑定到独立句柄。
    func openChapter(_ identity: ChapterIdentity) async throws -> any SourceOpenedChapter {
        guard identity.comic.sourceID == sourceID,
              !identity.comic.comicID.isEmpty,
              let order = Int(identity.chapterID),
              order >= 1,
              identity.chapterID == String(order)
        else {
            throw ComicSourceError.invalidIdentity
        }

        let resolved = try await SourceServiceOperation.run(
            failureMessage: "阅读章节加载失败，order=\(order)",
            category: "Bika.Reader",
            mapError: SourceErrorMapper.map,
        ) {
            try await client.chapterContent(for: identity, order: order)
        }

        try Task.checkCancellation()
        return SourceChapterHandle(
            content: resolved.content,
            pageDescriptors: resolved.pageDescriptors,
            pageSession: pageSession,
            logCategory: "Bika.Reader",
            rules: BikaOpenedChapterRules(sourcePreferences: client.sourcePreferences),
            pagination: SourceChapterPagination(batchSize: resolved.batchSize) { [client] batchIndex in
                let result = try await SourceServiceOperation.run(
                    failureMessage: "阅读清单分页加载失败，order=\(order)，batch=\(batchIndex)",
                    category: "Bika.Reader",
                    mapError: SourceErrorMapper.map,
                ) {
                    try await client.chapterContent(for: identity, order: order, page: batchIndex + 1)
                }
                return SourceChapterPageBatch(
                    pages: result.content.pages,
                    descriptors: result.pageDescriptors,
                )
            },
        )
    }
}

/// Bika 私有页面规则：直连或 CDN 地址 + 画质 Header；读取后返回原始编码数据。
private struct BikaOpenedChapterRules: SourceOpenedChapterRules {
    /// Bika 图片线路偏好：每页下载时读取最新值，不改变页面 identity 或缓存归属。
    let sourcePreferences: BikaSourcePreferences

    func makeRequest(for descriptor: BikaPageDescriptor) -> URLRequest {
        let requestURL = BikaImageRequestContext.requestURL(
            for: descriptor.url,
            usesCDNAcceleration: sourcePreferences.usesImageCDNAcceleration(),
        )

        var request = URLRequest(url: requestURL, cachePolicy: .reloadIgnoringLocalCacheData)
        request.httpMethod = "GET"
        request.setValue(BikaConfiguration.API.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(BikaImageQuality.original.rawValue, forHTTPHeaderField: "image-quality")
        return request
    }

    func makePayload(
        from fileURL: URL,
        descriptor: BikaPageDescriptor,
    ) async throws -> SourcePagePayload {
        try await SourcePageFileReader.encodedPayload(from: fileURL)
    }
}

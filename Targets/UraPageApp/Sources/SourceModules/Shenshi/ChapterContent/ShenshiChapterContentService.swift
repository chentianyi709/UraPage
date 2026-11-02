import Alamofire
import Foundation

/// 实现绅士在线 Reader 与后续 Download 共用的无状态章节入口。
actor ShenshiChapterContentService: SourceChapterContentService {
    nonisolated let sourceID = ComicSourceID.shenshi

    /// 与绅士其它网页业务共享 Host、Cookie 和 User-Agent 状态的稳定 Client。
    private let client: ShenshiSourceClient

    /// Reader 与作品下载共用无业务拦截器、无 URLCache 的章节页 Session。
    private let pageSession = Session(
        configuration: SourceConfiguration.Session.pageTransferConfiguration(),
    )

    init(client: ShenshiSourceClient) {
        self.client = client
    }

    /// 打开当前作品的唯一章节，并把页面请求描述封装进独立句柄。
    func openChapter(_ identity: ChapterIdentity) async throws -> any SourceOpenedChapter {
        guard identity.comic.sourceID == sourceID,
              !identity.comic.comicID.isEmpty,
              identity.chapterID == identity.comic.comicID,
              identity.comic.comicID.utf8.allSatisfy({ (48 ... 57).contains($0) })
        else {
            throw ComicSourceError.invalidIdentity
        }

        let resolved = try await SourceServiceOperation.run(
            failureMessage: "阅读内容加载失败，id=\(identity.comic.comicID)",
            category: "Shenshi.Reader",
            mapError: SourceErrorMapper.map,
        ) {
            try await client.chapterContent(for: identity)
        }

        try Task.checkCancellation()
        return SourceChapterHandle(
            content: resolved.content,
            pageDescriptors: resolved.pageDescriptors,
            pageSession: pageSession,
            logCategory: "Shenshi.Reader",
            rules: ShenshiOpenedChapterRules(),
        )
    }
}

/// 绅士私有页面规则：网页提供的 User-Agent 与 Referer；读取后返回原始编码数据。
private struct ShenshiOpenedChapterRules: SourceOpenedChapterRules {
    func makeRequest(for descriptor: ShenshiPageDescriptor) -> URLRequest {
        var request = URLRequest(url: descriptor.url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.httpMethod = "GET"
        request.setValue(descriptor.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(descriptor.referer.absoluteString, forHTTPHeaderField: "Referer")
        return request
    }

    func makePayload(
        from fileURL: URL,
        descriptor: ShenshiPageDescriptor,
    ) async throws -> SourcePagePayload {
        try await SourcePageFileReader.encodedPayload(from: fileURL)
    }
}

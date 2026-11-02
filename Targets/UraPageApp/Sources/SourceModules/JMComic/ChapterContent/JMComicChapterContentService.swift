import Alamofire
import Foundation

/// 实现禁漫在线 Reader 与后续 Download 共用的无状态章节入口。
actor JMComicChapterContentService: SourceChapterContentService {
    nonisolated let sourceID = ComicSourceID.jm

    /// 与禁漫其它业务共享 Host、Session 和远程 Setting 的稳定 Client。
    private let client: JMComicSourceClient

    /// Reader 与作品下载共用无 API 拦截器、无 URLCache 的章节页 Session。
    private let pageSession = Session(
        configuration: SourceConfiguration.Session.pageTransferConfiguration(),
    )

    init(client: JMComicSourceClient) {
        self.client = client
    }

    /// 打开章节，并把页面请求描述封装进独立的不可变句柄。
    func openChapter(_ identity: ChapterIdentity) async throws -> any SourceOpenedChapter {
        guard identity.comic.sourceID == sourceID,
              !identity.comic.comicID.isEmpty,
              !identity.chapterID.isEmpty
        else {
            throw ComicSourceError.invalidIdentity
        }

        let resolved = try await SourceServiceOperation.run(
            failureMessage: "阅读章节加载失败，chapterID=\(identity.chapterID)",
            category: "JM.Reader",
            mapError: SourceErrorMapper.map,
        ) {
            try await client.chapterContent(for: identity)
        }

        try Task.checkCancellation()
        return SourceChapterHandle(
            content: resolved.content,
            pageDescriptors: resolved.pageDescriptors,
            pageSession: pageSession,
            logCategory: "JM.Reader",
            rules: JMComicOpenedChapterRules(),
        )
    }
}

/// 禁漫私有页面规则：无自定义 Header，读取后交给解扰 worker。
private struct JMComicOpenedChapterRules: SourceOpenedChapterRules {
    func makeRequest(for descriptor: JMComicPageDescriptor) -> URLRequest {
        var request = URLRequest(url: descriptor.url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.httpMethod = "GET"
        return request
    }

    func makePayload(
        from fileURL: URL,
        descriptor: JMComicPageDescriptor,
    ) async throws -> SourcePagePayload {
        try await JMComicPagePayloadWorker.process(descriptor: descriptor, from: fileURL)
    }
}

/// 在并发执行器上完成禁漫单页读取与解扰，避免阻塞章节状态 Actor。
private enum JMComicPagePayloadWorker {
    @concurrent
    static func process(
        descriptor: JMComicPageDescriptor,
        from fileURL: URL,
    ) async throws -> SourcePagePayload {
        // 读取入口本身是 @concurrent，返回后仍在并发执行器上继续解扰。
        let data = try await SourcePageFileReader.data(from: fileURL)
        return try JMComicImageUnscrambler.pagePayload(from: data, descriptor: descriptor)
    }
}

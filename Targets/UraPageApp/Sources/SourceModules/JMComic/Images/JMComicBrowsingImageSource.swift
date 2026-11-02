import Foundation

/// 禁漫普通图片规则：缓存身份只由 locator 决定，实际请求才读取远程 Setting 的图片线路。
struct JMComicBrowsingImageSource: SourceBrowsingImageSource {
    private let client: JMComicSourceClient
    private let requestContext = JMComicImageRequestContext()

    /// 与禁漫公开 Services 共享同一个稳定 Source Client。
    init(client: JMComicSourceClient) {
        self.client = client
    }

    /// 缓存未命中后才准备业务环境：图片 Host 来自远程 Setting。
    func prepare() async throws -> JMComicRemoteSetting {
        try await client.preparedState().setting
    }

    /// 不读取远程 Setting，直接从稳定 locator 生成缓存身份。
    func resource(for reference: ComicImageReference) throws -> SourceImageResource {
        try requestContext.resource(for: reference)
    }

    /// 用准备阶段的图片 Host 组成完整请求。
    func request(for resource: SourceImageResource, preparation: JMComicRemoteSetting) throws -> URLRequest {
        try requestContext.request(for: resource.reference, imageHost: preparation.imageHost)
    }
}

import Foundation

/// 绅士普通图片规则：缓存身份只由 locator 决定，实际请求才准备当前页面 Host 与 User-Agent。
struct ShenshiBrowsingImageSource: SourceBrowsingImageSource {
    private let client: ShenshiSourceClient
    private let requestContext = ShenshiImageRequestContext()

    /// 与绅士公开 Services 共享同一个稳定 Source Client。
    init(client: ShenshiSourceClient) {
        self.client = client
    }

    /// 缓存未命中后才准备当前页面的 Host 与 User-Agent。
    func prepare() async throws -> ShenshiPreparedState {
        try await client.preparedState()
    }

    /// 不读取页面 Host，直接从稳定 locator 生成缓存身份。
    func resource(for reference: ComicImageReference) throws -> SourceImageResource {
        try requestContext.resource(for: reference)
    }

    /// 用准备阶段的页面地址与 User-Agent 组成完整请求。
    func request(
        for resource: SourceImageResource,
        preparation: ShenshiPreparedState,
    ) throws -> URLRequest {
        try requestContext.request(
            for: resource.reference,
            baseURL: preparation.baseURL,
            userAgent: preparation.userAgent,
        )
    }
}

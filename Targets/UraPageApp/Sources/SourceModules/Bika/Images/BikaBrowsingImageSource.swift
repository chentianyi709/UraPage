import Foundation

/// 哔咔普通图片规则：列表等图片共享延迟画质快照，详情封面使用引用指定的画质；请求时按当前 CDN 开关改写地址。
struct BikaBrowsingImageSource: SourceBrowsingImageSource {
    /// 页面内所有普通图片共享同一份延迟画质快照。
    private let requestContext: BikaImageRequestContext

    /// 创建首次资源解析时读取画质、且不持有 Credential 或 Session 的规则。
    init(sourcePreferences: BikaSourcePreferences) {
        requestContext = BikaImageRequestContext(sourcePreferences: sourcePreferences)
    }

    /// 按引用固定画质或页面浏览画质解析隔离的缓存身份。
    func resource(for reference: ComicImageReference) throws -> SourceImageResource {
        try requestContext.resource(for: reference)
    }

    /// 缓存未命中后按当前 CDN 开关解析实际请求；哔咔无需额外运行时准备。
    func request(for resource: SourceImageResource, preparation: Void) throws -> URLRequest {
        try requestContext.request(for: resource.reference)
    }
}

import Foundation

/// 来源普通图片规则：由来源提供“怎么准备、怎么算缓存身份、怎么构造请求”。
///
/// 三个方法都不做错误映射：公共句柄统一在边界处映射，来源只需抛出本源错误。
/// 规则必须无共享可变输出：`prepare` 可被同一实例的多张图片并发调用。
protocol SourceBrowsingImageSource: Sendable {
    /// 实际请求前需要准备的来源运行时值（Host、UA、远程 Setting）；无需准备时用 `Void`。
    associatedtype Preparation: Sendable

    /// 缓存未命中后、构造请求前调用。
    func prepare() async throws -> Preparation

    /// 生成稳定缓存身份；不触网、不读可变偏好，可在准备完成前调用。
    func resource(for reference: ComicImageReference) throws -> SourceImageResource

    /// 用已准备的值构造完整请求（地址、Header、CDN 规则）。
    func request(for resource: SourceImageResource, preparation: Preparation) async throws -> URLRequest
}

extension SourceBrowsingImageSource where Preparation == Void {
    /// 无需运行时准备的来源直接返回 `Void`。
    func prepare() async throws {}
}

/// 页面级普通图片服务：来源只提供规则，兜底顺序与错误映射只实现一次（§19.3）。
///
/// 由 `<来源>Services.makeBrowsingImages()` 在页面组合边界创建，
/// 每个浏览体验持有一个实例；缓存由 `BrowsingImageScope` 负责，本类型自身不缓存。
struct SourceBrowsingImageService<Source: SourceBrowsingImageSource>: ComicImageService {
    private let source: Source

    init(source: Source) {
        self.source = source
    }

    func resource(for reference: ComicImageReference) throws -> SourceImageResource {
        do {
            return try source.resource(for: reference)
        } catch {
            throw SourceErrorMapper.map(error)
        }
    }

    func request(for resource: SourceImageResource) async throws -> URLRequest {
        do {
            let preparation = try await source.prepare()
            return try await source.request(for: resource, preparation: preparation)
        } catch {
            throw SourceErrorMapper.map(error)
        }
    }
}

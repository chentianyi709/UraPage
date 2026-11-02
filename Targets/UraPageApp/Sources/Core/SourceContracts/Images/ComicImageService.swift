import Foundation

/// 定义具体漫画源分别解析稳定缓存身份和实际网络请求的能力。
///
/// 由来源在页面组合边界创建，生命周期与页面体验一致；
/// 不能提升为长期全局实例，否则页面级画质等快照会泄漏到其它页面。
protocol ComicImageService: Sendable {
    /// 纯本地解析缓存身份。
    ///
    /// 只能校验 reference、规范化 locator，并读取已在内存中的有界进程内快照
    /// （例如某来源的页面级画质快照）；不得读取 Host、远程 Setting、Credential、
    /// 网络或磁盘，也不得改变已经建立的图片身份。
    func resource(for reference: ComicImageReference) throws -> SourceImageResource

    /// 仅在缓存未命中后解析实际请求。
    ///
    /// 返回 Foundation `URLRequest`；调用方不得自行拼接 Host 或 Header。
    /// 实现不得重新决定与 `SourceImageResource.cacheKey` 冲突的资源身份。
    func request(for resource: SourceImageResource) async throws -> URLRequest
}

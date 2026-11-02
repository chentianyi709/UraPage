/// 保存普通远程图片的稳定引用和可在网络请求前使用的缓存标识。
///
/// `cacheKey` 由来源在 `ComicImageService.resource(for:)` 中生成，
/// 必须只依赖图片身份、规范化资源路径和内容参数，
/// 不依赖 Host、Credentials、网络或磁盘。
struct SourceImageResource: Hashable, Sendable {
    let reference: ComicImageReference
    let cacheKey: String

    /// 创建不依赖 Host、Setting、Credential 或网络状态的图片资源身份。
    init(reference: ComicImageReference, cacheKey: String) {
        self.reference = reference
        self.cacheKey = cacheKey
    }
}

/// 普通远程图片（封面、缩略图、头像）的用途，防止不同用途的缓存互相冲突。
enum ComicImagePurpose: String, Hashable, Codable, Sendable {
    case cover
    case thumbnail
    case avatar
}

/// 描述一张普通远程图片的稳定身份，不用于 Reader 章节页。
///
/// `locator` 是由所属来源解释的请求定位信息，可以保留相对路径、Host + path
/// 或公开完整地址；公共层不解析其内部格式。来源在自己的 `resource(for:)` 中把它
/// 组装成只含身份参数的 identityURL，缓存 Key 使用 identityURL 的 path 与非空 query。
///
/// 约束：
/// - `locator` 会随引用持久化并用于实际请求，不要写入 Token、Cookie、一次性验证码
///   或短期签名值；真实请求 URL 由来源的 `request(for:)` 构造。
/// - `ownerID` 由来源 Mapper 提供：有明确所属业务对象时使用该对象 ID；没有所属业务
///   对象的图片（如头像）由来源决定并在所有入口保持一致——惯用**空字符串**（合法值），
///   有稳定账号身份时也可用账号 ID，否则同一张图在不同入口会生成不同缓存。
///   公共缓存生成器原样编码该值，不按 `purpose` 改写；封面引用的 `ownerID` 必须是
///   作品 ID，供下载资产路径直接由引用推导。
/// - `assetIdentity` 是下载封面等资产文件名的稳定身份（path，或需要 query 时的
///   `path?query`）；`nil` 时只使用 locator 的 path。locator 含请求参数（例如禁漫默认
///   封面的 `?v=<update_at>`）时不会进入资产文件名；需要按 query 区分封面内容的来源
///   在 `assetIdentity` 中显式提供稳定身份。
/// - 来源的 `ComicImageService.resource(for:)` 必须只依赖这些纯本地值生成缓存身份；
///   缓存未命中后，`request(for:)` 才读取运行时 Host、Setting 或认证状态。
struct ComicImageReference: Hashable, Codable, Sendable {
    let sourceID: ComicSourceID

    /// 图片所属业务对象 ID；没有所属对象时为合法空字符串。
    let ownerID: String

    let locator: String
    let purpose: ComicImagePurpose
    let variant: String?

    /// 下载资产文件名的稳定身份；只影响下载封面文件名，不参与远程缓存身份。
    let assetIdentity: String?

    /// 创建一张普通远程图片的稳定引用。
    init(
        sourceID: ComicSourceID,
        ownerID: String,
        locator: String,
        purpose: ComicImagePurpose,
        variant: String?,
        assetIdentity: String? = nil,
    ) {
        self.sourceID = sourceID
        self.ownerID = ownerID
        self.locator = locator
        self.purpose = purpose
        self.variant = variant
        self.assetIdentity = assetIdentity
    }
}

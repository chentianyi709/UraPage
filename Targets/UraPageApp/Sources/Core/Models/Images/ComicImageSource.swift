/// 展示层图片来源：远程引用，或已下载的本地资产。
///
/// 只用于展示值（列表卡片、详情封面、书架快照），让在线与离线共用同一套结构。
/// 远程图片的网络与缓存管线仍使用 `ComicImageReference`（来源 `ComicImageService`
/// 据此生成稳定缓存身份与请求）；本地封面也由同一引用推导资产位置。
enum ComicImageSource: Hashable, Codable, Sendable {
    /// 远程图片引用，交给来源图片服务解析请求。
    case remote(ComicImageReference)

    /// 已下载的本地封面资产；文件位置由封面引用推导，缺少引用时显示占位。
    case downloaded(reference: ComicImageReference?)
}

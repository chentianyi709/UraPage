import Foundation

/// 依据禁漫漫画标识与服务端封面字段创建稳定的封面引用。
///
/// - 服务端未提供封面时使用固定相对路径，并把更新时间作为 `?v=<update_at>` 写入 locator；
/// - 服务端提供封面时原样保留（含查询参数）。
///
/// `?v=` 只是请求侧的版本参数（供服务器与中间缓存识别）：远程缓存身份与下载封面文件名
/// 都在 `JMComicCoverIdentity` 中去掉它，因此封面随章节更新不会让缓存与资产文件跟着换；
/// 真实请求仍带完整 locator。相对路径由 `ComicImageService` 在本地或请求时基于图片 Host 解析。
func makeJMCoverReference(
    comicID: String,
    image: String,
    updatedAt: Int,
) -> ComicImageReference {
    let locator = image.isEmpty
        ? "\(JMComicConfiguration.Image.defaultCoverRelativePath(comicID: comicID))?v=\(updatedAt)"
        : image

    return ComicImageReference(
        sourceID: .jm,
        ownerID: comicID,
        locator: locator,
        purpose: .cover,
        variant: nil,
        assetIdentity: JMComicCoverIdentity.assetIdentity(for: locator),
    )
}

/// 禁漫封面的稳定身份：去掉请求专用的 `v` 版本参数，只保留 path 与其余 query。
///
/// 缓存身份（`resource(for:)`）与下载封面文件名共用同一份规则；请求侧继续使用原始
/// locator，因此服务端在地址上看到的 `?v=` 不变。
enum JMComicCoverIdentity {
    /// 去掉 `v` 参数后的 locator；query 为空时连 `?` 一起去掉。
    static func locatorWithoutVersion(_ locator: String) -> String {
        guard var components = URLComponents(string: locator),
              let query = components.percentEncodedQuery
        else {
            return locator
        }

        let items = query
            .split(separator: "&", omittingEmptySubsequences: true)
            .filter { item in
                String(item) != "v" && !item.hasPrefix("v=")
            }
        components.percentEncodedQuery = items.isEmpty ? nil : items.joined(separator: "&")

        return components.string ?? locator
    }

    /// 下载封面文件的稳定身份：去掉 `v` 后取 path 与非空 query，Host 不参与。
    static func assetIdentity(for locator: String) -> String {
        SourceImageIdentity.pathAndQuery(ofLocator: locatorWithoutVersion(locator))
    }
}

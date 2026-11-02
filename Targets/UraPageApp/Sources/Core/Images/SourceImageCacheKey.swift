import CryptoKit
import Foundation

/// 为所有漫画源的普通远程图片生成格式一致且不暴露原始地址的缓存 Key。
///
/// 身份组成按固定顺序：
///
/// ```text
/// sourceID + purpose + ownerID + percentEncodedPath + [percentEncodedQuery] + variant
/// ```
///
/// query 只在非空时进入身份；经 `IdentityKeyEncoder.v1` 无歧义编码后再计算 SHA-256，
/// 最终格式为 `image.v1.<sourceID>.<purpose>.<小写十六进制摘要>`。
///
/// 约束：
/// - 只读取传入 identityURL 的 percent-encoded path 与非空 query；scheme、Host、port、
///   userinfo、fragment 永不参与，因此切换业务 Host、图片 Host 或 CDN 后仍命中同一缓存。
/// - identityURL 由来源组装，只放参与缓存身份的查询参数；临时签名、Token、一次性参数
///   不得放进去，真实请求 URL 由 `request(for:)` 另行构造。需要按内容版本区分时也可以
///   由来源写入 `variant`，公共层不猜测参数含义。
/// - 原样编码 `reference.ownerID`，不按 purpose 改写；头像由来源决定取值并在所有入口
///   保持一致（惯用空字符串，有稳定账号身份时也可用账号 ID）。
enum SourceImageCacheKey {
    /// 使用图片稳定引用与来源组装的缓存身份 URL 生成缓存 Key。
    ///
    /// - Parameters:
    ///   - reference: 图片稳定引用；`variant` 用于区分同一位置的内容版本。
    ///   - identityURL: 来源组装的缓存身份 URL，只含参与身份的 path 与 query。
    /// - Returns: 不依赖 Host、Credential 或网络状态，可直接用于查询缓存的 Key。
    static func make(for reference: ComicImageReference, identityURL: URL) -> String {
        let identity = SourceImageIdentity.components(of: identityURL)

        var keyComponents = [
            reference.sourceID.rawValue,
            reference.purpose.rawValue,
            reference.ownerID,
            identity.path,
        ]
        // 只在非空时加入 query；没有 variant 时仍占一个空串，避免"缺项"与"空值"算出不同键。
        if let query = identity.query {
            keyComponents.append(query)
        }
        keyComponents.append(reference.variant ?? "")

        let digest = SourceDigest.hex(SHA256.hash(data: IdentityKeyEncoder.v1(keyComponents)))

        return "image.v1.\(reference.sourceID.rawValue).\(reference.purpose.rawValue).\(digest)"
    }
}

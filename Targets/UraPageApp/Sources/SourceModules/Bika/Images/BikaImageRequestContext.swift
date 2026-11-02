import Foundation
import Synchronization

/// 普通图片使用首次资源解析固定的浏览画质；明确标记固定画质的引用按其自身规则请求。
final class BikaImageRequestContext: Sendable {
    private let sourcePreferences: BikaSourcePreferences
    private let imageQualitySnapshot = Mutex<BikaImageQuality?>(nil)

    /// 保留首次请求前读取当前画质的能力。
    init(sourcePreferences: BikaSourcePreferences) {
        self.sourcePreferences = sourcePreferences
    }

    /// 从完整 locator 和引用指定或页面固定的画质生成不依赖 CDN 开关的缓存身份。
    ///
    /// 哔咔当前不使用 query 区分图片内容，identityURL 显式只取 path；将来需要时在这里
    /// 保留对应查询参数即可，公共生成器已支持非空 query。
    func resource(for reference: ComicImageReference) throws -> SourceImageResource {
        let directImageURL = try validatedImageURL(for: reference)
        let imageQuality = imageQuality(for: reference)
        let cacheReference = ComicImageReference(
            sourceID: reference.sourceID,
            ownerID: reference.ownerID,
            locator: reference.locator,
            purpose: reference.purpose,
            variant: BikaImageCacheVariant.make(for: imageQuality),
            assetIdentity: reference.assetIdentity,
        )

        return SourceImageResource(
            reference: reference,
            cacheKey: SourceImageCacheKey.make(
                for: cacheReference,
                identityURL: SourceImageIdentity.urlWithoutQuery(directImageURL),
            ),
        )
    }

    /// 缓存未命中后，生成不携带 API Credential 的直连或 CDN 图片请求。
    func request(for reference: ComicImageReference) throws -> URLRequest {
        let directImageURL = try validatedImageURL(for: reference)
        let imageQuality = imageQuality(for: reference)

        // CDN 开关按每次实际请求读取，让设置变化无需重建页面图片服务即可生效。
        let imageURL = Self.requestURL(
            for: directImageURL,
            usesCDNAcceleration: sourcePreferences.usesImageCDNAcceleration(),
        )
        var request = URLRequest(url: imageURL)
        request.setValue(BikaConfiguration.API.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(imageQuality.rawValue, forHTTPHeaderField: "image-quality")
        return request
    }

    /// 按哔咔规则把图片直连地址的首个 picacomic 片段改写为 go2778。
    ///
    /// 只处理请求地址，不参与缓存身份；关闭 CDN 或地址不含该片段时原样返回。
    static func requestURL(for directURL: URL, usesCDNAcceleration: Bool) -> URL {
        guard usesCDNAcceleration else {
            return directURL
        }

        let directURLString = directURL.absoluteString
        guard let sourceRange = directURLString.range(of: "picacomic") else {
            return directURL
        }

        let acceleratedURLString = directURLString.replacingCharacters(in: sourceRange, with: "go2778")
        // 改写后的字符串可能不再是合法 URL（极端 locator）：回退直连地址，不让整张图片失败。
        return URL(string: acceleratedURLString) ?? directURL
    }

    /// 校验引用并解析服务端提供的完整直连地址。
    private func validatedImageURL(for reference: ComicImageReference) throws -> URL {
        guard let directImageURL = URL(string: reference.locator),
              directImageURL.scheme != nil,
              directImageURL.host != nil
        else {
            throw ComicSourceError.invalidResponse
        }

        return directImageURL
    }

    /// 引用自带固定画质时优先使用；否则读取页面的浏览画质快照。
    private func imageQuality(for reference: ComicImageReference) -> BikaImageQuality {
        BikaImageCacheVariant.fixedQuality(from: reference.variant) ?? resolvedImageQuality()
    }

    /// 普通图片在第一次资源解析或请求时固定页面的浏览画质。
    private func resolvedImageQuality() -> BikaImageQuality {
        imageQualitySnapshot.withLock { snapshot in
            if let snapshot {
                return snapshot
            }

            let currentQuality = sourcePreferences.browsingImageQuality()
            snapshot = currentQuality
            return currentQuality
        }
    }
}

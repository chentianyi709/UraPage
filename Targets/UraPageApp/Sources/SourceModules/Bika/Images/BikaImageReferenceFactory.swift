import Foundation

/// 把哔咔 API 返回的文件服务信息转换为稳定图片引用。
///
/// 只负责“引用身份”的组合（fileServer + path → locator、可选固定画质 variant），
/// 不处理 CDN 或实际请求；普通图片画质由图片服务在缓存 miss 后确定。
enum BikaImageReferenceFactory {
    /// 使用服务端 locator 创建稳定图片引用；详情封面可固定原画，其余图片沿用浏览画质。
    ///
    /// locator 无法构成合法地址时返回 `nil`：调用方按“该项不可用”处理，
    /// 需要整体失败的调用方（如详情封面）自行决定是否升级为响应级错误。
    static func make(
        ownerID: String,
        fileServer: String,
        path: String,
        purpose: ComicImagePurpose,
        fixedQuality: BikaImageQuality? = nil,
    ) -> ComicImageReference? {
        guard let imageURL = imageURL(fileServer: fileServer, path: path) else {
            return nil
        }

        return ComicImageReference(
            sourceID: .bika,
            ownerID: ownerID,
            locator: imageURL.absoluteString,
            purpose: purpose,
            variant: fixedQuality.map { BikaImageCacheVariant.make(for: $0) },
        )
    }

    /// 按哔咔文件服务规则组合 `fileServer`、可选 `static` 目录和图片路径；无法构成合法地址时返回 `nil`。
    static func imageURL(fileServer: String, path: String) -> URL? {
        let trimmedServer = fileServer.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let serverURL = URL(string: trimmedServer),
              serverURL.scheme != nil,
              serverURL.host != nil,
              !trimmedPath.isEmpty
        else {
            return nil
        }

        // 非 static 服务需要补一段 `static` 目录，再拼接去首斜杠的路径。
        var imageURL = serverURL
        if !trimmedServer.localizedCaseInsensitiveContains("static") {
            imageURL.append(path: "static")
        }
        imageURL.append(path: String(trimmedPath.drop(while: { $0 == "/" })))
        return imageURL
    }
}

/// 编码和校验哔咔普通图片缓存键使用的质量 variant。
enum BikaImageCacheVariant {
    private static let prefix = "quality.v1."

    /// 将图片质量编码为稳定、版本化且不包含秘密的 variant。
    static func make(for imageQuality: BikaImageQuality) -> String {
        prefix + imageQuality.rawValue
    }

    /// 仅解析来源明确写入引用的固定画质；普通引用没有 variant，仍读取页面画质快照。
    static func fixedQuality(from variant: String?) -> BikaImageQuality? {
        guard let variant, variant.hasPrefix(prefix) else { return nil }

        return BikaImageQuality(rawValue: String(variant.dropFirst(prefix.count)))
    }
}

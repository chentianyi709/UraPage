import Alamofire
import Foundation

extension JMComicSourceClient {
    /// 请求远程 Setting；已选图源失效时，使用首个候选再请求一次。
    static func fetchRemoteSetting(
        using session: Session,
        imageSourceKey: Int,
    ) async throws -> JMComicRemoteSetting {
        let setting = try await requestRemoteSetting(using: session, imageSourceKey: imageSourceKey)
        guard !setting.imageSources.contains(where: { $0.key == imageSourceKey }),
              let fallbackKey = setting.imageSources.first?.key,
              fallbackKey != imageSourceKey
        else {
            return setting
        }

        return try await requestRemoteSetting(using: session, imageSourceKey: fallbackKey)
    }

    /// 使用指定图片分流 Key 完成一次 `/setting` 请求和转换。
    private static func requestRemoteSetting(
        using session: Session,
        imageSourceKey: Int,
    ) async throws -> JMComicRemoteSetting {
        let timestamp = Int(Date().timeIntervalSince1970)
        let dto = try await session
            .request(
                "/setting",
                method: .get,
                parameters: ["app_img_shunt": imageSourceKey, "t": timestamp],
                encoding: URLEncoding.default,
            )
            .jmComicDecodedResponse(as: JMComicRemoteSettingDTO.self)

        guard let imageHost = URL(string: dto.imageHost) else {
            throw JMComicAPIError.invalidSetting
        }

        // 图源名称面向设置页展示，统一转成简体中文便于识别。
        let imageSources = dto.imageSources.map {
            JMComicImageSource(title: $0.title.convertedToSimplifiedChinese(), key: $0.key)
        }

        return JMComicRemoteSetting(
            imageHost: imageHost,
            imageSources: imageSources,
            selectedImageSourceKey: imageSourceKey,
        )
    }
}

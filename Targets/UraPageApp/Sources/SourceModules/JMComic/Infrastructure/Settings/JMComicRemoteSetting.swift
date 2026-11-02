import Foundation
import ReerCodable

/// 禁漫业务 API 返回的当前图片 Host 和可选图片分流。
struct JMComicRemoteSetting: Sendable {
    let imageHost: URL
    let imageSources: [JMComicImageSource]
    let selectedImageSourceKey: Int
}

/// 描述禁漫提供的一项图片分流选择。
struct JMComicImageSource: Identifiable, Hashable, Sendable {
    let title: String
    let key: Int

    /// 使用服务端数字 Key 作为菜单中的稳定标识。
    var id: Int {
        key
    }
}

/// 向禁漫来源设置页面提供当前图源与实际图片 Host。
struct JMComicImageSourceSelectionSnapshot: Hashable, Sendable {
    let imageSources: [JMComicImageSource]
    let selectedKey: Int
    let activeImageHost: URL
}

/// 解码 `/setting` 返回的最小配置字段。
@Decodable
struct JMComicRemoteSettingDTO: Decodable, ReerCodableDelegate {
    @CodingKey("img_host")
    let imageHost: String

    @CodingKey("app_shunts")
    let imageSources: [JMComicImageSourceDTO]
}

/// 解码图片分流标题及可能以字符串返回的数字 Key。
@Decodable
struct JMComicImageSourceDTO: Decodable, ReerCodableDelegate {
    let title: String

    @FlexibleType
    let key: Int
}

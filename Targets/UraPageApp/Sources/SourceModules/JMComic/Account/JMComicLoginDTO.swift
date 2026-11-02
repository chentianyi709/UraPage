import Foundation
import ReerCodable

/// 解码禁漫 `/login` 返回的凭证与展示资料。
///
/// 只有展示需要的字段；`uid` 与数字字段服务端可能给出字符串或数字，交给 `@FlexibleType` 兼容。
@Decodable
struct JMComicLoginDTO: Decodable, ReerCodableDelegate, Sendable {
    /// JWT，登录后作为 `Authorization: Bearer` 发送。
    @CodingKey("jwttoken")
    let jwtToken: String

    /// 会话值，登录后作为 `Cookie: AVS=` 发送。
    let s: String

    @FlexibleType
    let uid: String

    let username: String

    /// 展示名称；服务端可能为空。
    @DecodingDefault("")
    let fname: String

    /// 头像 locator；服务端可能只给文件名或为空。
    @DecodingDefault("")
    let photo: String

    @FlexibleType
    @DecodingDefault(0)
    let level: Int

    @CodingKey("level_name")
    @DecodingDefault("")
    let levelName: String
}

extension JMComicLoginDTO {
    /// 登录成功后要保存的凭证。
    var credential: JMComicCredential {
        JMComicCredential(jwtToken: jwtToken, sessionValue: s)
    }

    /// 登录成功后要缓存并展示的账号资料。
    var accountProfile: JMComicAccountProfile {
        let trimmedPhoto = photo.trimmingCharacters(in: .whitespacesAndNewlines)
        return JMComicAccountProfile(
            accountID: uid,
            username: username,
            displayName: fname.isEmpty ? username : fname,
            level: level,
            levelName: levelName,
            // 头像只保存稳定引用；实际请求由禁漫图片服务补全相对路径与当前图片 Host。
            avatar: trimmedPhoto.isEmpty ? nil : ComicImageReference(
                sourceID: .jm,
                ownerID: uid,
                locator: trimmedPhoto,
                purpose: .avatar,
                variant: nil,
            ),
        )
    }
}

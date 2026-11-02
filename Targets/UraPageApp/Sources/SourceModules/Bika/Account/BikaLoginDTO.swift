import ReerCodable

/// 解码哔咔 `auth/sign-in` 返回的登录 Token。
@Decodable
struct BikaLoginDTO: Decodable, ReerCodableDelegate, Sendable {
    let token: String
}

/// 解码哔咔 `users/profile` 返回的账号资料包装。
@Decodable
struct BikaUserProfileDTO: Decodable, ReerCodableDelegate, Sendable {
    let user: BikaAccountUserDTO
}

/// 解码账号资料中展示需要的字段。
@Decodable
struct BikaAccountUserDTO: Decodable, ReerCodableDelegate, Sendable {
    @CodingKey("_id")
    let id: String

    @DecodingDefault("")
    let email: String

    /// 昵称；服务端可能未设置。
    @DecodingDefault("")
    let name: String

    /// 登录成功后要缓存并展示的账号资料。
    var accountProfile: BikaAccountProfile {
        BikaAccountProfile(accountID: id, email: email, nickname: name)
    }
}

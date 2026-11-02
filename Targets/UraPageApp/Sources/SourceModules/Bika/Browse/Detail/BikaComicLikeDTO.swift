import ReerCodable

/// 表示哔咔点赞切换接口可识别的服务端动作。
enum BikaComicLikeAction: String, Decodable, Sendable {
    case like
    case unlike
}

/// 解码哔咔点赞切换接口返回的最终动作。
@Decodable
struct BikaComicLikeActionDTO: Decodable, ReerCodableDelegate, Sendable {
    let action: BikaComicLikeAction
}

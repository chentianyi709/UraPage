/// 保存禁漫点赞接口确认后的业务结果。
struct JMComicLikeResult: Sendable {
    /// 服务端是否确认点赞成功。
    let succeeded: Bool

    /// 服务端返回的展示消息；失败时可能为空。
    let message: String
}

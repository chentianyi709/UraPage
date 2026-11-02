/// 来源账号 owner 对外发布的访问事实。
///
/// 只表达“能否访问本源需登录内容”这一件事：不含用户名、Cookie 或任何凭证正文；
/// 失败区分“本机凭证问题”与“在线校验失败”，都用安全错误表达，不用字符串伪装登录状态。
nonisolated enum SourceAccessSnapshot: Equatable, Sendable {
    /// 正在恢复或校验本源账号；门禁静默等待，不提前渲染页面。
    case checking

    /// 未登录，或现有凭证已失效；门禁显示未登录提示并提供登录入口。
    case unauthenticated

    /// 已登录，可访问本源受保护内容。
    case authenticated

    /// 恢复或校验失败；门禁显示失败态与重试入口。
    case failed(Failure)

    /// 访问事实无法确定的原因。
    nonisolated enum Failure: Equatable, Sendable {
        /// 本机凭证读取或解码失败（Keychain 问题，不是服务端响应问题）。
        case credentialUnavailable

        /// 在线校验失败；用公共安全错误表达。
        case checkFailed(ComicSourceError)
    }
}

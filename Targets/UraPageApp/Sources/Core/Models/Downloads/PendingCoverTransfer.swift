/// 封面任务的启动输入：作品身份与作品行已存的封面引用。
///
/// 引用为远程引用（已保存的本地封面不产生传输任务）；入队启动与冷启动恢复都只读作品行列，
/// 不解码离线详情。
struct PendingCoverTransfer: Sendable {
    let identity: ComicIdentity
    let cover: ComicImageSource
}

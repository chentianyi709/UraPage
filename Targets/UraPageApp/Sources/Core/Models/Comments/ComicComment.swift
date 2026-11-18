import Foundation

/// 一条跨来源的只读评论；回复也用同一类型表示。
///
/// 只保留界面要展示的四项（头像／时间／名称／正文）与回复关系；点赞数、楼层、设备等
/// 来源私有信息不进入本类型，避免公共层被来源字段牵着走。
struct ComicComment: Identifiable, Hashable, Sendable {
    let id: String

    let nickname: String

    /// 被回复的用户名；回复楼主时为 `nil`（整段回复区都属于楼主，不需要再点名），
    /// 回复子评论时才有值。顶级评论本身不使用这个字段。
    ///
    /// 界面统一按「有值就显示『回复 @某某』」处理；来源拿不到这条信息时填 `nil`，
    /// 不代表回复对象就是楼主。
    let replyTargetName: String?

    /// 头像引用；来源没有头像或头像不可用时为 `nil`，由界面显示占位。
    let avatar: ComicImageReference?

    /// 已经格式化好的时间文案；来源未提供时为空串。
    let dateText: String

    let content: String

    /// 随顶级评论一并返回的回复；需要单独请求的来源这里为空。
    let replies: [ComicComment]

    /// 服务端声明的回复总数；已取得的回复数优先，避免数量小于实际展示的回复。
    let replyCount: Int

    init(
        id: String,
        nickname: String,
        replyTargetName: String? = nil,
        avatar: ComicImageReference? = nil,
        dateText: String,
        content: String,
        replies: [ComicComment] = [],
        replyCount: Int? = nil,
    ) {
        self.id = id
        self.nickname = nickname
        self.replyTargetName = replyTargetName
        self.avatar = avatar
        self.dateText = dateText
        self.content = content
        self.replies = replies
        self.replyCount = max(replyCount ?? replies.count, replies.count)
    }
}

/// 一页评论。
///
/// `hasMore` 由来源按自己的分页字段给出；来源拿不到页码／总页数时为 `nil`，
/// 由公共层按累计条数与 `total` 折算——两者口径不一定一致（`total` 可能含回复，也可能缺失）。
struct ComicCommentPage: Sendable {
    let comments: [ComicComment]

    /// 服务端声明的评论总数；来源不提供时为 0。用于标题与 `hasMore` 缺失时的兜底折算。
    let total: Int

    /// 还有下一页；`nil` 表示来源无法判断。
    let hasMore: Bool?
}

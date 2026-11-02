import Foundation

/// 跨来源共享的普通漫画列表卡片最小展示值。
///
/// 只描述“列表卡片”所需的稳定身份与展示字段；作者、图片数量、日期等
/// 来源差异由各来源整理进 `subtitle`，公共层不解释其语义。
/// 不进入 SwiftData、下载 manifest 或其它来源体验。
struct ComicListItem: Identifiable, Hashable, Sendable {
    let identity: ComicIdentity
    let title: String

    /// 由来源整理的副标题（作者、图片数量、日期等）；没有时为 `nil`。
    let subtitle: String?

    let cover: ComicImageSource

    /// 来源给出的最近更新时间；没有时间概念的来源为 `nil`。
    ///
    /// 公共层不解释它的语义，也不据此绘制任何东西，只在卡片叠层里把它原样交回页面
    /// （页面自己的叠层决定显示什么，例如禁漫的「更新」标记）。
    let updatedAt: Date?

    /// 使用完整漫画身份作为列表稳定标识。
    var id: ComicIdentity {
        identity
    }

    init(
        identity: ComicIdentity,
        title: String,
        subtitle: String?,
        cover: ComicImageSource,
        updatedAt: Date? = nil,
    ) {
        self.identity = identity
        self.title = title
        self.subtitle = subtitle
        self.cover = cover
        self.updatedAt = updatedAt
    }
}

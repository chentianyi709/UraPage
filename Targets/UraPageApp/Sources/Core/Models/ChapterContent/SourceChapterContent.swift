import CoreGraphics
import Foundation

/// 章节元信息及首次取得的页面清单；pages 可只包含首批，index 始终为章内真实序号。
///
/// 只包含稳定展示值和页面身份；来源私有的请求描述保存在
/// 对应的 `SourceOpenedChapter`，不进入这里。
struct SourceChapterContent: Sendable {
    let identity: ChapterIdentity
    let title: String
    let pages: [ComicPage]
    let totalPageCount: Int

    /// 创建只包含稳定展示值的章节内容。
    init(identity: ChapterIdentity, title: String, pages: [ComicPage], totalPageCount: Int? = nil) {
        self.identity = identity
        self.title = title
        self.pages = pages
        self.totalPageCount = totalPageCount ?? pages.count
    }
}

/// 保存来源处理完成后交给通用 Reader 的单页内容。
enum SourcePagePayload: Sendable {
    /// 保留 GIF 等仍需由 Reader 解码的原始编码数据。
    case encoded(Data)

    /// 直接传递来源已经解扰完成的位图，避免重新编码再解码。
    case decoded(CGImage)
}

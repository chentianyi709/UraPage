import Foundation
import SwiftData

/// 每个作品与内容模式组合保存一条最新阅读位置和展示快照。
///
/// 在线与离线进度互不覆盖：`contentModeRawValue` 参与唯一约束，读取时按模式筛选。
/// 书架展示的作者与下载记录用同一种存法（`MultiValueText` 连接的文本列），
/// 不再是不可查询的数组属性。
@Model
final class StoredReadingProgress {
    // 一部作品在一个内容模式下只有一条进度。`#Unique` 自带唯一索引，单条读取直接走它。
    #Unique<StoredReadingProgress>([\.sourceID, \.comicID, \.contentModeRawValue])

    // 分页查询形状：内容模式等值 → 更新时间倒序 → 来源／作品做稳定 tiebreak。
    #Index<StoredReadingProgress>([\.contentModeRawValue, \.updatedAt, \.sourceID, \.comicID])

    var sourceID: String
    var comicID: String
    var contentModeRawValue: String

    var title: String
    var authorsText: String

    /// 封面引用（`ComicImageSource` 的 JSON 编码）；阅读记录不保存本地封面文件。
    var coverReferenceData: Data

    var chapterID: String
    var pageID: String
    var pageIndex: Int
    var chapterTitle: String
    var updatedAt: Date

    init(update: ReadingProgressUpdate, coverReferenceData: Data, updatedAt: Date) {
        let identity = update.comic.identity
        sourceID = identity.sourceID.rawValue
        comicID = identity.comicID
        contentModeRawValue = update.contentMode.rawValue
        title = update.comic.title
        authorsText = MultiValueText.joined(update.comic.authors)
        self.coverReferenceData = coverReferenceData
        chapterID = update.pageIdentity.chapter.chapterID
        pageID = update.pageIdentity.pageID
        pageIndex = update.pageIndex
        chapterTitle = update.chapterTitle
        self.updatedAt = updatedAt
    }

    /// 作者（拆分自 `authorsText`）；set 重新连接写回，展示与写入方不必知道存储形态。
    var authors: [String] {
        get { MultiValueText.values(from: authorsText) }
        set { authorsText = MultiValueText.joined(newValue) }
    }
}

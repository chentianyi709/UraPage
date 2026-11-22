import Foundation
import SwiftData

/// 一部已下载作品的行记录：列表与调度只读本行的列。
///
/// 展示列（身份、标题、作者／标签／分类、封面引用）、封面传输状态与**聚合投影**（`stateRawValue`／
/// 两个章节计数）都持久化在这里；投影由 `DownloadPersistence` 在同一事务内按章节行维护
/// （单一写者），列表读取只读投影。多值展示值以 `MultiValueText` 连接的文本列保存
/// （`authorsText`／`tagsText`／`categoriesText`），作为搜索谓词的直接匹配对象；
/// 读写经 `authors`／`tags`／`categories` 计算属性还原为数组。离线详情的其余字段在
/// `detailExtrasData`。章节级进度仍是运行时值，不落库。
///
/// `detailExtrasData` 是唯一的冷字段，刻意留在本行：实测（2026-11-21）拆到独立表
/// 在真实规模下只省 0.2–1.2 ms，却要多维护一张表、两条删除路径和一次按主键读取。
@Model
final class StoredDownloadWork {
    // 一部作品一条记录。`#Unique` 自带唯一索引，列表按作品取行直接走它。
    #Unique<StoredDownloadWork>([\.sourceID, \.comicID])

    // 下载记录分页：`sortGroup` 等值 + `sortAt` 定序 + 来源／作品做稳定 tiebreak。
    #Index<StoredDownloadWork>([\.sortGroup, \.sortAt, \.sourceID, \.comicID])

    var sourceID: String
    var comicID: String

    /// 下载记录卡片与离线详情共用的作品展示值；标题、作者、标签、分类只存这一份，不写进详情 blob。
    var title: String
    var authorsText: String
    var tagsText: String
    var categoriesText: String

    /// 封面引用（`ComicImageSource` 的 JSON 编码）；本地封面文件位置由引用推导。
    var coverReferenceData: Data

    /// 离线详情中除作品行列外的字段（`DownloadedComicDetailExtras` 的 JSON 编码）；
    /// 解码失败时离线详情报错，不请求在线数据补齐。
    var detailExtrasData: Data

    /// 封面自身的传输状态；作品聚合状态由封面与章节状态投影到下面三个字段。
    var coverStateRawValue: String

    /// 作品聚合状态投影（章节状态 + 封面状态）。
    ///
    /// 由 `DownloadPersistence` 在同一事务内用章节行维护（单一写者，不存在独立第二份真值）；
    /// 列表与离线门槛直接读投影，不再逐作品查章节行。章节级进度仍是运行时值，不落库。
    var stateRawValue: String

    /// 已完成章节数与已选章节总数；与聚合状态同一次投影一起更新。
    var completedChapterCount: Int
    var chapterCount: Int

    /// 下载记录排序分组：0 未完成、1 已完成；已完成组永远排在未完成组之后。
    ///
    /// 由持久化层在聚合投影变化时维护（与 `state` 同一事务），列表排序只读本列。
    private(set) var sortGroup: Int = 0

    /// 组内排序时间：未完成组是最近一次入队时间，已完成组是完成时间。
    ///
    /// 入队时写入 `now`；作品首次进入已完成时改写为完成时刻，使完成后排在已完成组首位。
    /// 分组与时间分开存，作品完成后回未完成组（补下章节）时仍能按入队时间恢复位置。
    var sortAt: Date = Date.distantPast

    init(
        identity: ComicIdentity,
        title: String,
        authors: [String],
        tags: [String],
        categories: [String],
        coverReferenceData: Data,
        detailExtrasData: Data,
        coverState: DownloadState,
        state: DownloadState,
        completedChapterCount: Int,
        chapterCount: Int,
        now: Date,
    ) {
        sourceID = identity.sourceID.rawValue
        comicID = identity.comicID
        self.title = title
        authorsText = MultiValueText.joined(authors)
        tagsText = MultiValueText.joined(tags)
        categoriesText = MultiValueText.joined(categories)
        self.coverReferenceData = coverReferenceData
        self.detailExtrasData = detailExtrasData
        coverStateRawValue = coverState.rawValue
        stateRawValue = state.rawValue
        self.completedChapterCount = completedChapterCount
        self.chapterCount = chapterCount
        sortGroup = state == .completed ? 1 : 0
        sortAt = now
    }

    /// 类型化的封面传输状态；无法识别的持久化值返回 `nil`（损坏记录），由读取方显式跳过。
    var coverState: DownloadState? {
        get { DownloadState(rawValue: coverStateRawValue) }
        set { coverStateRawValue = newValue?.rawValue ?? coverStateRawValue }
    }

    /// 类型化的作品聚合状态；无法识别的持久化值返回 `nil`（损坏记录），由读取方显式跳过。
    var state: DownloadState? {
        get { DownloadState(rawValue: stateRawValue) }
        set { stateRawValue = newValue?.rawValue ?? stateRawValue }
    }

    /// 写入聚合投影：状态、计数与排序分组一起更新，避免 `state` 与 `sortGroup` 各自漂移。
    ///
    /// 只有「从未完成变为完成」才把 `sortAt` 改写成完成时刻；之后补下章节回到未完成组时，
    /// 仍用原来的入队时间恢复位置。
    func applyProjection(
        state: DownloadState,
        completedChapterCount: Int,
        chapterCount: Int,
        now: Date,
    ) {
        let wasCompleted = self.state == .completed
        self.state = state
        self.completedChapterCount = completedChapterCount
        self.chapterCount = chapterCount

        if state == .completed {
            if !wasCompleted {
                sortGroup = 1
                sortAt = now
            }
        } else {
            sortGroup = 0
        }
    }

    /// 作者（拆分自 `authorsText`）；set 重新连接写回，展示与写入方不必知道存储形态。
    var authors: [String] {
        get { MultiValueText.values(from: authorsText) }
        set { authorsText = MultiValueText.joined(newValue) }
    }

    /// 标签（拆分自 `tagsText`）；其余同 `authors`。
    var tags: [String] {
        get { MultiValueText.values(from: tagsText) }
        set { tagsText = MultiValueText.joined(newValue) }
    }

    /// 分类（拆分自 `categoriesText`）；其余同 `authors`。
    var categories: [String] {
        get { MultiValueText.values(from: categoriesText) }
        set { categoriesText = MultiValueText.joined(newValue) }
    }

    /// 还原完整作品身份；`sourceID` 无法识别时返回 `nil`（损坏记录）。
    var identity: ComicIdentity? {
        guard let sourceID = ComicSourceID(rawValue: sourceID) else {
            return nil
        }

        return ComicIdentity(sourceID: sourceID, comicID: comicID)
    }
}

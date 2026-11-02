import Foundation
import SwiftData

/// 一部已下载作品的行记录：列表与调度只读本行的列。
///
/// 展示列（身份、标题、作者／标签／分类、封面引用）、封面传输状态与**聚合投影**（`stateRawValue`／
/// 两个章节计数）都持久化在这里；投影由 `DownloadPersistence` 在同一事务内按章节行维护
/// （单一写者），列表读取只读投影。多值展示值以 U+001F 连接的文本列保存
/// （`authorsText`／`tagsText`／`categoriesText`，各值不含连接符），作为搜索谓词的直接匹配对象；
/// 读写经 `authors`／`tags`／`categories` 计算属性还原为数组。离线详情的其余字段在
/// `detailExtrasData`，两者只在入队时一起写入，不各自持有副本；章节级进度仍是运行时值，不落库。
@Model
final class StoredDownloadedComic {
    #Index<StoredDownloadedComic>([\.sortGroup, \.sortAt, \.identityKey])

    @Attribute(.unique) var identityKey: String
    var sourceID: String
    var comicID: String

    /// 下载记录卡片与离线详情共用的作品展示值；标题、作者、标签、分类只存这一份，不写进详情 blob。
    ///
    /// 多值列用 U+001F 连接、供搜索直接匹配；读写经 `authors`／`tags`／`categories` 计算属性。
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
    var sortGroup: Int = 0

    /// 组内排序时间：未完成组是最近一次入队时间，已完成组是完成时间。
    ///
    /// 入队时写入 `now`；作品首次进入已完成时改写为完成时刻，使完成后排在已完成组首位。
    /// 分组与时间分开存，作品完成后回未完成组（补下章节）时仍能按入队时间恢复位置。
    var sortAt: Date = Date.distantPast

    var createdAt: Date
    var updatedAt: Date

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
        identityKey = Self.key(for: identity)
        sourceID = identity.sourceID.rawValue
        comicID = identity.comicID
        self.title = title
        authorsText = Self.joinedText(authors)
        tagsText = Self.joinedText(tags)
        categoriesText = Self.joinedText(categories)
        self.coverReferenceData = coverReferenceData
        self.detailExtrasData = detailExtrasData
        coverStateRawValue = coverState.rawValue
        stateRawValue = state.rawValue
        self.completedChapterCount = completedChapterCount
        self.chapterCount = chapterCount
        sortGroup = state == .completed ? 1 : 0
        sortAt = now
        createdAt = now
        updatedAt = now
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

    /// 作者（拆分自 `authorsText`）；set 重新连接写回，展示与写入方不必知道存储形态。
    var authors: [String] {
        get { Self.values(from: authorsText) }
        set { authorsText = Self.joinedText(newValue) }
    }

    /// 标签（拆分自 `tagsText`）；其余同 `authors`。
    var tags: [String] {
        get { Self.values(from: tagsText) }
        set { tagsText = Self.joinedText(newValue) }
    }

    /// 分类（拆分自 `categoriesText`）；其余同 `authors`。
    var categories: [String] {
        get { Self.values(from: categoriesText) }
        set { categoriesText = Self.joinedText(newValue) }
    }

    /// 还原完整作品身份；`sourceID` 无法识别时返回 `nil`（损坏记录）。
    var identity: ComicIdentity? {
        guard let sourceID = ComicSourceID(rawValue: sourceID) else {
            return nil
        }

        return ComicIdentity(sourceID: sourceID, comicID: comicID)
    }

    /// 多值文本列的连接符（Unit Separator）：不会出现在正常展示文本里，保证拆分无歧义。
    private static let valueSeparator = "\u{1F}"

    /// 多值展示值连接为可检索文本列；空数组得到空串。
    private static func joinedText(_ values: [String]) -> String {
        values.joined(separator: valueSeparator)
    }

    /// 文本列还原为多值展示值；空串得到空数组，保留空值元素。
    private static func values(from text: String) -> [String] {
        text.isEmpty ? [] : text.components(separatedBy: valueSeparator)
    }

    /// 长度前缀让任意两个完整作品身份都不会拼接碰撞（与 `StoredReadingHistory.key` 同款）。
    static func key(for identity: ComicIdentity) -> String {
        key(sourceID: identity.sourceID.rawValue, comicID: identity.comicID)
    }

    /// 用已持久化的原始字段生成同一身份 key（供按原始行查询的持久化代码复用）。
    static func key(sourceID: String, comicID: String) -> String {
        "\(sourceID.count):\(sourceID)\(comicID.count):\(comicID)"
    }
}

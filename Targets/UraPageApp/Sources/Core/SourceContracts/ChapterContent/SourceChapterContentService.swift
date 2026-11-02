import Foundation

/// 定义 Reader 与下载真实共用的、无会话状态的章节入口。
///
/// 由来源 Services 稳定持有，不保存已打开章节；
/// 每次 `openChapter` 返回独立句柄，多个句柄可共享来源内部稳定 Client。
protocol SourceChapterContentService: Sendable {
    /// 本源稳定标识。
    var sourceID: ComicSourceID { get }

    /// 打开指定章节，返回绑定该章来源私有描述的访问句柄。
    func openChapter(_ identity: ChapterIdentity) async throws -> any SourceOpenedChapter
}

/// 绑定章节元信息及其来源私有页面访问描述，清单按批次增量取得。
///
/// 句柄只持有该章内容，允许不同页面并发下载与处理，
/// 不使用共享的“当前页面”或可变缓冲区。
protocol SourceOpenedChapter: Sendable {
    /// 稳定章节元信息（真实总图片数与首批清单），不要求已经取齐所有分页。
    var content: SourceChapterContent { get }

    /// 真实接口分页大小；非分页来源为 `nil`（整章随 `content` 一次取得）。
    ///
    /// 作品下载据此计算分页请求数与进度分母；Reader 不使用。
    var pageBatchSize: Int? { get }

    /// 按章内零基序号取得其所在批次；仅请求目标批次，命中清单缓存不联网。
    /// 返回整批已解析页面，Reader 可复用清单为附近槽位预加载图片。
    func pages(containing index: Int) async throws -> [ComicPage]

    /// 使用本源页面 Session，把当前章节的一页下载到调用方提供的临时文件。
    func downloadPage(_ page: ComicPage, to fileURL: URL) async throws

    /// 从已下载文件读取当前章节页面，返回来源完成解密/解扰后的内容。
    ///
    /// 不删除调用方拥有的输入文件；单次处理状态归本次调用，
    /// 不能通过共享状态干扰同一句柄内其它并发页面。
    func pagePayload(for page: ComicPage, from fileURL: URL) async throws -> SourcePagePayload
}

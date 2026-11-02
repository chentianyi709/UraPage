import Alamofire
import Foundation

/// 来源私有页面描述：至少能自报页面 identity，句柄据此建立页面索引。
///
/// 描述只保存本源请求/解扰所需的信息（URL、Header、密钥等），不含公共展示值。
protocol SourcePageDescriptor: Sendable {
    var identity: PageIdentity { get }
}

/// 来源私有页面规则：句柄把重复流程写完，来源只提供“怎么请求”和“怎么处理字节”。
///
/// 两个方法都必须是纯函数式的：相同输入产生相同结果，不读写共享可变状态。
/// `makePayload` 中的解密、解扰、解码属于重活，必须放进 `@concurrent` worker 或独立 Actor。
protocol SourceOpenedChapterRules: Sendable {
    associatedtype Descriptor: SourcePageDescriptor

    /// 用本源规则构造一次页面下载请求（地址、Header、缓存策略）。
    func makeRequest(for descriptor: Descriptor) -> URLRequest

    /// 把已下载文件的字节转成公共载荷。
    func makePayload(from fileURL: URL, descriptor: Descriptor) async throws -> SourcePagePayload
}

/// 所有来源共用的“已打开章节”句柄（§19.3）。
///
/// 收拢三件逐字重复的事：
/// 1. 页面身份校验（属于当前章节、序号与内容一致）；
/// 2. 用来源规则构造请求，通过来源自己的前台 Session 下载到调用方独占文件；
/// 3. 通过来源规则把已下载字节转成 `SourcePagePayload`，并统一失败日志与错误映射。
///
/// 为什么不是基类继承：Swift 的 `actor` 不支持继承，因此改为“公共 final actor 句柄 +
/// 来源规则值”。规则值不产生转发方法，也不让来源实现公共流程，方向与“公共类 + 来源私有部分”
/// 一致（见 `架构重构方案.md` §19.3 的说明）。
///
/// 生命周期与并发：由 `<来源>ChapterContentService.openChapter` 创建，一个句柄独占一章；
/// 章节元信息不可变；增量清单与在途请求由 actor 隔离，多个页面可并发下载与处理。
/// 句柄由调用方（Reader/下载）在章节结束时释放，释放即释放本源页面描述。
final actor SourceChapterHandle<Rules: SourceOpenedChapterRules>: SourceOpenedChapter {
    /// 只包含稳定展示值与有序页面身份的章节内容。
    nonisolated let content: SourceChapterContent

    /// 页面 identity 到来源私有描述的映射；首批与后续批次共用校验。
    private var pageDescriptors: [PageIdentity: Rules.Descriptor]

    private var pagesByIndex: [Int: ComicPage]
    private nonisolated let pagination: SourceChapterPagination<Rules.Descriptor>?
    private var pageBatches: [Int: [ComicPage]]

    /// 无 API 拦截器和 URLCache 的本源页面 Session。
    private let pageSession: Session

    /// 同一批次的页面共享请求；最后一个等待者取消时才取消底层任务。
    private struct BatchJob {
        let id: UUID
        let task: Task<SourceChapterPageBatch<Rules.Descriptor>, any Error>
        var waiters: Set<UUID>
    }

    private var batchJobs: [Int: BatchJob] = [:]

    /// 失败日志分类，例如 `"JM.Reader"`。
    private let logCategory: String

    /// 来源私有规则；无状态或持有本源稳定 owner。
    private let rules: Rules

    init(
        content: SourceChapterContent,
        pageDescriptors: [Rules.Descriptor],
        pageSession: Session,
        logCategory: String,
        rules: Rules,
        pagination: SourceChapterPagination<Rules.Descriptor>? = nil,
    ) {
        self.content = content
        self.pagination = pagination
        self.pageSession = pageSession
        pageBatches = [0: content.pages]
        pagesByIndex = Dictionary(uniqueKeysWithValues: content.pages.map { ($0.index, $0) })
        self.pageDescriptors = Dictionary(
            pageDescriptors.map { ($0.identity, $0) },
            uniquingKeysWith: { first, _ in first },
        )
        self.logCategory = logCategory
        self.rules = rules
    }

    deinit {
        batchJobs.values.forEach { $0.task.cancel() }
    }

    /// 作品下载直接读这里的真实分页大小，计算分页请求数与进度分母；非分页来源为 `nil`。
    nonisolated var pageBatchSize: Int? {
        pagination?.batchSize
    }

    /// 清单解析与图片下载使用同一位置入口；无需为“下一页”另建 Reader 状态。
    func pages(containing index: Int) async throws -> [ComicPage] {
        try Task.checkCancellation()
        guard (0 ..< content.totalPageCount).contains(index) else {
            throw ComicSourceError.invalidIdentity
        }

        let batchIndex = pagination.map { index / $0.batchSize } ?? 0
        if let pages = pageBatches[batchIndex] {
            return pages
        }
        if let pagination {
            try await loadBatch(batchIndex, using: pagination)
        }

        try Task.checkCancellation()
        guard let pages = pageBatches[batchIndex] else {
            // 不变量：上面要么命中清单缓存，要么 loadBatch 成功写入了该批次。
            throw ComicSourceError.invalidResponse
        }

        return pages
    }

    private func loadBatch(
        _ batchIndex: Int,
        using pagination: SourceChapterPagination<Rules.Descriptor>,
    ) async throws {
        let waiterID = UUID()
        let job: BatchJob
        if var existing = batchJobs[batchIndex] {
            existing.waiters.insert(waiterID)
            batchJobs[batchIndex] = existing
            job = existing
        } else {
            job = BatchJob(
                id: UUID(),
                task: Task { try await pagination.loadBatch(batchIndex) },
                waiters: [waiterID],
            )
            batchJobs[batchIndex] = job
        }
        defer { releaseWaiter(waiterID, batchIndex: batchIndex, jobID: job.id) }
        try await withTaskCancellationHandler {
            let batch = try await job.task.value
            try Task.checkCancellation()
            guard batchJobs[batchIndex]?.id == job.id else { throw CancellationError() }

            if pageBatches[batchIndex] == nil {
                insert(batch, at: batchIndex)
            }
        } onCancel: {
            Task { await self.releaseWaiter(waiterID, batchIndex: batchIndex, jobID: job.id) }
        }
    }

    private func insert(
        _ batch: SourceChapterPageBatch<Rules.Descriptor>,
        at batchIndex: Int,
    ) {
        pageBatches[batchIndex] = batch.pages
        for page in batch.pages {
            pagesByIndex[page.index] = page
        }
        for descriptor in batch.descriptors {
            pageDescriptors[descriptor.identity] = descriptor
        }
    }

    private func releaseWaiter(_ waiterID: UUID, batchIndex: Int, jobID: UUID) {
        guard var job = batchJobs[batchIndex], job.id == jobID else { return }

        job.waiters.remove(waiterID)
        if job.waiters.isEmpty {
            batchJobs[batchIndex] = nil
            job.task.cancel()
        } else {
            batchJobs[batchIndex] = job
        }
    }

    /// 把当前章节的一页下载到调用方提供的临时文件；身份校验先于网络或文件操作。
    func downloadPage(_ page: ComicPage, to fileURL: URL) async throws {
        guard fileURL.isFileURL else {
            throw ComicSourceError.invalidIdentity
        }

        let descriptor = try resolveDescriptor(for: page)
        let request = rules.makeRequest(for: descriptor)

        try await SourceServiceOperation.run(
            failureMessage: failureMessage(phase: "下载", page: page),
            category: logCategory,
            mapError: SourceErrorMapper.map,
        ) {
            try await SourcePageTransfer.download(request, using: pageSession, to: fileURL)
        }
    }

    /// 从已下载文件读取当前章节页面，返回来源完成解密/解扰后的内容。
    func pagePayload(for page: ComicPage, from fileURL: URL) async throws -> SourcePagePayload {
        guard fileURL.isFileURL else {
            throw ComicSourceError.invalidIdentity
        }

        let descriptor = try resolveDescriptor(for: page)

        return try await SourceServiceOperation.run(
            failureMessage: failureMessage(phase: "处理", page: page),
            category: logCategory,
            mapError: SourceErrorMapper.map,
        ) {
            try await rules.makePayload(from: fileURL, descriptor: descriptor)
        }
    }

    /// 校验页面属于当前章节并返回其来源私有描述；不满足即视为非法输入。
    ///
    /// 只在此处校验一次：调用方拿到的 `ComicPage` 可能来自别的章节或已过期，
    /// 来源规则因此不需要重复判断。
    private func resolveDescriptor(for page: ComicPage) throws -> Rules.Descriptor {
        guard page.identity.chapter == content.identity,
              pagesByIndex[page.index] == page,
              let descriptor = pageDescriptors[page.identity]
        else {
            throw ComicSourceError.invalidIdentity
        }

        return descriptor
    }

    /// 统一的失败日志文案；只含公开身份与页码，不含 URL、Header 或响应内容。
    private func failureMessage(phase: String, page: ComicPage) -> String {
        "阅读页\(phase)失败，comicID=\(content.identity.comic.comicID)，"
            + "chapterID=\(content.identity.chapterID)，page=\(page.index)"
    }
}

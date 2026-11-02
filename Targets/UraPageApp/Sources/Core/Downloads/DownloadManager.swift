import Foundation

/// 下载调度 owner：队列、并发名额、暂停／继续／重试、进度与变更广播。
///
/// 只做短事务与网络编排，不在本 actor 内做文件扫描或图片编码；正式资产由 `DownloadAssetStore` 管理，
/// 记录由 `DownloadPersistence` 管理，章节页传输由 `PageTransferCoordinator` 管理。同一作品同时只有
/// 一个调度任务；单来源同时下载的作品数受 `workLimitPerSource` 限制，单作品内的页面处理并发受
/// `pageConcurrencyPerWork` 限制，两者的乘积再由 `pageBudget` 的全局名额压住。所有网络传输都由前台任务发起。
///
/// 具体职责按扩展拆分：调度、章节下载、页下载、删除、Host 切换、暂停／继续／重试、
/// 读取、进度投影、页传输与变更广播分别在同目录的 `DownloadManager+*.swift`。
actor DownloadManager {
    nonisolated let catalog: SourceRuntimeCatalog
    nonisolated let assetStore: DownloadAssetStore
    nonisolated let browsingImageCache: any BrowsingImageCacheReading

    /// 章节页传输 owner；Reader 与作品下载共用同一缓存优先前台下载器。
    let transfers: PageTransferCoordinator

    /// 全部作品共享的在途页任务名额；只约束作品下载，Reader 预加载不经过这里。
    let pageBudget: DownloadPageBudget

    /// 单来源同时下载的作品上限；用户可在通用设置调整，调度时读当前值。
    private(set) var workLimitPerSource: Int

    /// 单作品内页面处理并发上限（每页解扰／编码／写盘任务组的名额）；下一批页生效。
    private(set) var pageConcurrencyPerWork: Int

    /// 下载记录列表页大小；列表刷新的「至少一页」与触底续载都以它为准，页大小只在这里定义。
    nonisolated static let summariesPageSize = 30

    private var persistenceTask: Task<DownloadPersistence, any Error>?

    /// 用户暂停意图；暂停时插入，继续／重试时移除。用于阻止被暂停的作品被重新调度。
    var pausedWorks: Set<ComicIdentity> = []
    /// 正在执行用户删除的作品；期间拒绝新的入队与暂停／继续／重试，避免删除过程中被重新调度。
    var removingWorks: Set<ComicIdentity> = []
    /// 正在写入入队事务的作品及重叠入队次数；删除／清空必须等全部入队收尾，
    /// 避免删除完成后入队又写回记录。
    var enqueuingWorks: [ComicIdentity: Int] = [:]
    /// 正在删除无法读取的下载记录或无记录资产；期间拒绝新入队，避免新作品记录写入与
    /// 资产目录创建的间隙被当作孤立资产，或旧资产删除误伤刚开始的新下载。
    var isCleaningDownloadStorage = false
    /// 正在清除全部下载；期间拒绝新入队与启动，避免清空过程中把记录重新写回来。
    var isRemovingAll = false
    /// 正在启动、尚未登记进 `activeRuns` 的作品，避免并发重复启动。
    var startingWorks: Set<ComicIdentity> = []
    /// 等待启动收尾的删除／清空操作；启动的 `defer` 统一唤醒，避免删除与启动交错。
    var startingWaiters: [ComicIdentity: [CheckedContinuation<Void, Never>]] = [:]
    /// 每个运行中作品的控制句柄；暂停或 Host 切换时置停止标记，让协作式循环尽快停止。
    var runControls: [ComicIdentity: RunControl] = [:]
    var activeRuns: [ComicIdentity: RunState] = [:]
    /// 每个作品的封面任务；与作品调度相互独立（入队即启动、不受每来源作品名额限制）。
    var coverRuns: [ComicIdentity: CoverRunState] = [:]
    var activeCounts: [ComicSourceID: Int] = [:]
    var pendingRuns: [ComicIdentity] = []
    var runtimes: [ComicIdentity: WorkRuntime] = [:]
    /// 正在等待旧 run 收尾的 Host 重启作品；期间禁止启动新 run，避免新旧任务交错。
    var hostRestartingWorks: Set<ComicIdentity> = []
    /// 每个来源的 Host 代次；页传输按代次隔离旧线路上的在途请求。
    var hostGenerations: [ComicSourceID: UInt64] = [:]
    /// 每个来源的 Host 事件订阅任务；进程生命周期内常驻。
    var hostObservationTasks: [Task<Void, Never>] = []
    var changeContinuations: [UUID: AsyncStream<DownloadChange>.Continuation] = [:]
    /// 结构版本；只在作品集合或作品／章节状态变化时递增，随每条事件下发。
    var structuralRevision: UInt64 = 0

    init(
        catalog: SourceRuntimeCatalog,
        assetStore: DownloadAssetStore,
        browsingImageCache: any BrowsingImageCacheReading,
        cacheReading: any ChapterImageCacheReading,
        workLimitPerSource: Int,
        pageConcurrencyPerWork: Int,
    ) {
        self.catalog = catalog
        self.assetStore = assetStore
        self.browsingImageCache = browsingImageCache
        self.workLimitPerSource = workLimitPerSource
        self.pageConcurrencyPerWork = pageConcurrencyPerWork
        transfers = PageTransferCoordinator(cacheReading: cacheReading)
        pageBudget = DownloadPageBudget(limit: AppConfiguration.Downloads.maximumInFlightPageTasks)
    }

    // MARK: - 并发上限

    /// 应用用户在通用设置里选择的并发上限。
    ///
    /// 作品上限提高后立刻补位排队作品；降低不打断在跑作品，只影响后续调度。
    /// 页并发由 `downloadPages` 在下一批取当前值，在途页不被中断。
    func applyConcurrencyLimits(workLimitPerSource: Int, pageConcurrencyPerWork: Int) async {
        self.workLimitPerSource = workLimitPerSource
        self.pageConcurrencyPerWork = pageConcurrencyPerWork
        await pump()
    }

    // MARK: - 入队与生命周期

    /// 把详情页选中的章节加入下载队列；已完成的章节不重复下载。
    ///
    /// 返回是否写入成功；持久化失败只记录日志、不启动调度，调用方据此决定是否提示成功。
    @discardableResult
    func enqueue(_ requests: [DownloadChapterRequest]) async -> Bool {
        guard !requests.isEmpty else { return true }

        // 清除全部下载或清理下载存储期间不接受新章节，避免清理判定与记录／资产写入交错。
        guard !isRemovingAll, !isCleaningDownloadStorage else { return false }

        // 正在删除的作品不再接受新章节，避免删除过程中把记录或资产重新写回来。
        // 只要混入被删除的作品就整单拒绝：部分成功会让调用方误以为全部章节都已入队。
        guard requests.allSatisfy({ !removingWorks.contains($0.identity.comic) }) else {
            return false
        }

        // 入队事务与删除互斥：写库期间登记作品，删除／清空看到后拒绝并发操作，
        // 避免删除先完成、入队随后又把作品记录写回来。重叠入队按次数计数，
        // 先结束的入队不能提前移除另一个入队的保护。
        let acceptedComics = Set(requests.map(\.identity.comic))
        for comic in acceptedComics {
            enqueuingWorks[comic, default: 0] += 1
        }
        defer {
            for comic in acceptedComics {
                guard let remaining = enqueuingWorks[comic] else { continue }

                if remaining <= 1 {
                    enqueuingWorks[comic] = nil
                } else {
                    enqueuingWorks[comic] = remaining - 1
                }
            }
        }

        do {
            try await persistence().upsert(requests: requests, now: Date())
        } catch {
            AppLogger.error(
                "下载入队写入失败，errorType=\(String(reflecting: type(of: error)))",
                category: "App.Download",
            )
            return false
        }
        publishStructural()
        for comic in acceptedComics {
            // 入队追加了章节行；已有运行时（或正在启动）的作品把计数缓存对齐到新投影。
            await refreshRuntimeCounts(for: comic)
            // 封面与作品调度无关：点击下载即立即开始处理，不等作品名额。
            await startCoverTransfer(comic)
            await requestRun(comic)
        }
        return true
    }

    /// 启动时把上次遗留的 downloading 章节与封面回退为排队，并在 App 下次运行时重新从前台调度。
    func reconcileAfterLaunch() async {
        do {
            try await persistence().recoverInterrupted()
        } catch {
            AppLogger.error(
                "下载启动对账失败，errorType=\(String(reflecting: type(of: error)))",
                category: "App.Download",
            )
            return
        }

        var resumedComics: [ComicIdentity] = []
        var seenComics: Set<ComicIdentity> = []
        do {
            for chapter in try await persistence().pendingChapters()
                where seenComics.insert(chapter.comic).inserted {
                resumedComics.append(chapter.comic)
            }
        } catch {
            AppLogger.error(
                "下载任务恢复列表读取失败，errorType=\(String(reflecting: type(of: error)))",
                category: "App.Download",
            )
        }
        do {
            for transfer in try await persistence().pendingCoverTransfers() {
                // 封面与作品调度无关：恢复时同样立即开始处理。
                await startCoverTransfer(transfer.identity)
            }
        } catch {
            AppLogger.error(
                "下载封面启动恢复失败，errorType=\(String(reflecting: type(of: error)))",
                category: "App.Download",
            )
        }

        for comic in resumedComics {
            await requestRun(comic)
        }
    }

    // MARK: - 辅助

    func persistence() async throws -> DownloadPersistence {
        if let persistenceTask {
            return try await persistenceTask.value
        }

        let task = Task { try await DownloadPersistence.makeDefault() }
        persistenceTask = task
        do {
            return try await task.value
        } catch {
            persistenceTask = nil
            throw error
        }
    }

    // MARK: - 内部状态

    /// 单个运行中作品的停止标记；置位后协作式循环尽快停止。
    ///
    /// 用户暂停与 Host 重启都只需要「尽快退出」这一语义，停止原因由各自入口记录，不在运行控制里区分。
    final class RunControl {
        private(set) var isStopped = false

        func stop() {
            isStopped = true
        }
    }

    struct RunState {
        let token: UUID
        let task: Task<Void, Never>
    }

    /// 一个独立封面任务的身份与句柄；token 用于拒绝被暂停或替换后的旧结果。
    struct CoverRunState {
        let token: UUID
        let task: Task<Void, Never>
    }

    struct ChapterRuntime {
        let identity: ChapterIdentity
        var state: DownloadState
        /// 单位总数（章节信息＋后续分页＋页图片）；打开章节前未知。
        var totalUnitCount: Int?
        /// 已完成单位数（含缓存复用与已下载页）。
        var completedUnitCount: Int
    }

    struct WorkRuntime {
        let comic: ComicIdentity
        let title: String
        let authors: [String]
        var cover: ComicImageSource
        var coverState: DownloadState
        var chapters: [ChapterRuntime]
        /// 作品级章节计数缓存：只以持久化投影为准，运行时不自行统计。
        var chapterCount: Int
        var completedChapterCount: Int
    }
}

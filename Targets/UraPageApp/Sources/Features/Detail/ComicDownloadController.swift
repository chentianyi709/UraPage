import Observation
import SwiftUI

/// 详情页下载交互的公共页面级状态 owner，替代三个来源各自复制的下载接线。
///
/// 持有作品级与章节级下载状态，负责：读取状态、构建选章条目、入队、按状态处理底栏点击。
/// 与来源无关：来源只把本源章节映射成 `DownloadChapterCandidate` 并给出作品快照。
@MainActor
@Observable
final class ComicDownloadController {
    private let manager: DownloadManager
    private let identity: ComicIdentity

    private(set) var workState: DownloadState?
    private(set) var chapterStates: [ChapterIdentity: DownloadState] = [:]

    /// 选章弹窗是否展示；详情显示章节入口且存在可勾选章节时打开，确认或取消后关闭。
    var isSheetPresented = false

    @ObservationIgnored private var streamTask: Task<Void, Never>?
    /// 已应用的结构版本；版本变化才重读状态，逐页进度事件不会触发数据库读取。
    @ObservationIgnored private var appliedRevision: UInt64 = 0
    /// 最近一次状态读取是否失败；失败时上面的状态不代表本地真实情况，不能当作「没有下载记录」。
    @ObservationIgnored private var hasUnresolvedStateFailure = false

    init(manager: DownloadManager, identity: ComicIdentity) {
        self.manager = manager
        self.identity = identity
    }

    deinit {
        streamTask?.cancel()
    }

    /// 订阅下载变更流，使底栏图标与选章弹窗状态在下载推进时同步；重复调用保持单条订阅。
    func start() {
        guard streamTask == nil else { return }

        let manager = manager
        streamTask = Task { [weak self] in
            let stream = await manager.makeChangeStream()
            for await change in stream {
                guard let self else { return }
                guard change.revision != appliedRevision else { continue }

                appliedRevision = change.revision
                await refresh()
            }
        }
    }

    /// 首次调用时创建控制器并启动订阅，每次调用都刷新状态；离线模式无需调用。
    @MainActor
    static func makeOrRefresh(
        existing: ComicDownloadController?,
        manager: DownloadManager,
        identity: ComicIdentity,
    ) async -> ComicDownloadController {
        let controller: ComicDownloadController
        if let existing {
            controller = existing
        } else {
            controller = ComicDownloadController(manager: manager, identity: identity)
            controller.start()
        }
        await controller.refresh()
        return controller
    }

    /// 读取作品与各章节的当前下载状态；失败时记录日志、保留上一次已知状态并标记为未知。
    ///
    /// 不使用空数组覆盖：本地记录读取失败与“没有下载”是两种不同事实，
    /// 保留旧状态至少不会把已下载作品伪装成未下载；标记供下载入口拒绝按未知状态入队。
    func refresh() async {
        do {
            let status = try await manager.downloadStatus(for: identity)
            workState = status.workState
            chapterStates = Dictionary(uniqueKeysWithValues: status.items.compactMap { item in
                item.state.map { (item.identity, $0) }
            })
            hasUnresolvedStateFailure = false
        } catch {
            hasUnresolvedStateFailure = true
            AppLogger.error(
                "详情下载状态读取失败，source=\(identity.sourceID.rawValue)，errorType=\(String(reflecting: type(of: error)))",
                category: "App.Download",
            )
        }
    }

    /// 选章弹窗条目；章节列表由来源按展示顺序给出（需要倒序的来源自行先倒序）。
    func selectionItems(for chapters: [DownloadChapterCandidate]) -> [DownloadChapterSelectionItem] {
        chapters.map {
            DownloadChapterSelectionItem(
                identity: $0.identity,
                title: $0.title,
                order: $0.order,
                state: chapterStates[$0.identity],
            )
        }
    }

    /// 处理底栏「下载」按钮点击。
    ///
    /// - Parameters:
    ///   - chapters: 本源可下载章节（按展示顺序）。
    ///   - snapshot: 作品快照，用于首次下载落库。
    ///   - presentsChapterSelection: 详情是否显示章节入口；显示时打开选章弹窗，否则直接入队全部候选。
    func handleDownloadTap(
        chapters: [DownloadChapterCandidate],
        snapshot: DownloadedComicDetailSnapshot,
        presentsChapterSelection: Bool,
    ) async {
        // 下载会在详情页之外继续；点击时刷新聚合状态，避免一直停留在入队时的旧状态。
        await refresh()

        // 状态未知时不入队：本地记录读取失败不能当成「没有下载记录」，否则会重复入队。
        guard !hasUnresolvedStateFailure else {
            ToastCenter.shared.show("下载状态读取失败，请稍后重试", type: .error)
            return
        }

        // 没有可下载章节时不再静默返回；已有下载记录仍按作品状态反馈。
        guard !chapters.isEmpty else {
            if let workState {
                handleExistingDownload(workState)
            } else {
                ToastCenter.shared.show("暂无可下载章节", type: .warning)
            }
            return
        }

        if presentsChapterSelection {
            // 所有章节都已在下载记录中（排队／下载中／暂停／已完成）时没有可加入或重试的章节，
            // 选章弹窗只会是没有可选项的空面板；改为按作品级状态提示，失败时重试。
            guard selectionItems(for: chapters).contains(where: \.isSelectable) else {
                if let workState {
                    handleExistingDownload(workState)
                } else {
                    // 有章节行却没有作品聚合投影：记录不完整，不能提示「已下载」。
                    ToastCenter.shared.show("下载状态不可用，请稍后重试", type: .error)
                }
                return
            }

            isSheetPresented = true
            return
        }

        // 详情未显示章节入口时没有可选目录，直接入队全部可下载章节。
        // 现有来源此时均为单章；按全部候选入队，避免来源规则变化时静默漏下后续章节。
        if let workState {
            handleExistingDownload(workState)
        } else {
            enqueue(downloadRequests(for: chapters, snapshot: snapshot))
        }
    }

    /// 作品已在下载记录中时的点击反馈：按聚合状态提示，失败时重试。
    ///
    /// 单章节作品重复点击与多章节作品已无可选章节时共用；失败重试会重新排队失败章节
    /// 并重试未保存的封面。
    private func handleExistingDownload(_ state: DownloadState) {
        switch state {
        case .queued:
            ToastCenter.shared.show("等待下载")

        case .downloading:
            ToastCenter.shared.show("正在下载")

        case .paused:
            ToastCenter.shared.show("已在下载记录中暂停")

        case .completed:
            ToastCenter.shared.show("已下载")

        case .failed:
            Task {
                await manager.retry(identity)
                await refresh()
            }
        }
    }

    /// 入队用户在选章弹窗勾选的章节。
    func enqueue(
        _ selected: Set<ChapterIdentity>,
        chapters: [DownloadChapterCandidate],
        snapshot: DownloadedComicDetailSnapshot,
    ) {
        enqueue(
            downloadRequests(
                for: chapters.filter { selected.contains($0.identity) },
                snapshot: snapshot,
            ),
        )
    }

    /// 把详情候选映射为下载请求；选章与直接入队共用同一映射。
    private func downloadRequests(
        for chapters: [DownloadChapterCandidate],
        snapshot: DownloadedComicDetailSnapshot,
    ) -> [DownloadChapterRequest] {
        chapters.map {
            DownloadChapterRequest(
                identity: $0.identity,
                chapterTitleSnapshot: $0.title,
                chapterOrderSnapshot: $0.order,
                comicSnapshot: snapshot,
            )
        }
    }

    private func enqueue(_ requests: [DownloadChapterRequest]) {
        guard !requests.isEmpty else { return }

        Task {
            let didEnqueue = await manager.enqueue(requests)
            await refresh()
            if didEnqueue {
                ToastCenter.shared.show("已加入下载队列")
            } else {
                ToastCenter.shared.show("加入下载队列失败", type: .error)
            }
        }
    }
}

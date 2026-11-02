import Foundation

/// 来源无关的动态 Host 发现与选择状态机。
///
/// 候选列表与实际地址**只保存在内存**：本次 App 进程内有效，切换来源仍有效，
/// App 退出即失效；因此每次启动都会重新发现候选。
///
/// 偏好写入：**只有用户显式 `select(baseURL:)` 才持久化已选地址**；首次解析只读取已选
/// 偏好用于挑选 active，不写入。因此没有手动选择时，每次启动都从候选列表第一个地址开始。
///
/// 语义：不提供“自动模式”，也不随机选择；首次解析固定到候选列表中的具体地址。
/// 由来源 Client 持有（进程级稳定），Host 切换的在途编排（新请求等待、失败保留原环境）由 Client 完成。
actor SourceHostProvider {
    /// 来源注入的发现实现：发现失败时可自行决定是否使用来源内置兜底。
    typealias CandidateDiscovery = @Sendable () async throws -> [SourceHostCandidate]

    private let sourceID: ComicSourceID
    private let discoverCandidates: CandidateDiscovery
    private let preferenceStore = SourceHostPreferenceStore()

    /// 当前进程已解析的完整状态；切源不销毁 Provider，因此可继续复用。
    private var cachedState: SourceHostSelectionSnapshot?

    /// 合并同时到达的首次解析。
    private var resolutionTask: Task<SourceHostSelectionSnapshot, any Error>?

    init(sourceID: ComicSourceID, discoverCandidates: @escaping CandidateDiscovery) {
        self.sourceID = sourceID
        self.discoverCandidates = discoverCandidates
    }

    /// 返回本次进程选定的 API Base URL。
    func baseURL() async throws -> URL {
        try await resolvedState().activeBaseURL
    }

    /// 返回候选线路（地址＋展示名）与当前实际地址，供来源设置使用。
    func selectionSnapshot() async throws -> SourceHostSelectionSnapshot {
        try await resolvedState()
    }

    /// 固定到候选列表中的一个具体地址。
    ///
    /// 返回切换后的快照与是否实际变化；重复选择当前地址返回 `didChange == false`，
    /// 不写偏好、不重建环境。地址不在候选中时抛出 `baseURLUnavailable`。
    /// 这是唯一会持久化地址偏好的入口。
    func select(baseURL: URL) async throws -> (snapshot: SourceHostSelectionSnapshot, didChange: Bool) {
        let current = try await resolvedState()

        // 重复选择当前地址：直接返回，不写偏好、不重建环境。
        guard current.activeBaseURL != baseURL else {
            return (current, false)
        }

        // 只接受候选列表中的地址，页面不能提交任意 URL。
        guard SourceHostSelectionResolver.candidate(
            matching: baseURL.absoluteString,
            in: current.candidates,
        ) != nil else {
            throw SourceHostSelectionError.baseURLUnavailable
        }

        // 这是唯一持久化地址偏好的入口：下次启动若该地址仍存在则沿用。
        await preferenceStore.setSelectedBaseURL(baseURL, for: sourceID)
        let next = SourceHostSelectionSnapshot(candidates: current.candidates, activeBaseURL: baseURL)
        cachedState = next
        AppLogger.debug("Host 已切换", category: "Source.Host")
        return (next, true)
    }

    /// 返回或创建当前进程唯一的一次首次解析任务。
    private func resolvedState() async throws -> SourceHostSelectionSnapshot {
        try Task.checkCancellation()
        // 进程内已有解析结果直接复用（切源不销毁 Provider）。
        if let cachedState {
            return cachedState
        }

        if let resolutionTask {
            return try await SourceSharedWait.value(of: resolutionTask)
        }

        // 工作自身负责提交与清理；调用方取消只结束等待，不影响其它页面。
        // 不让多个等待者分别清理任务，避免旧失败结果清掉后来发起的新解析。
        let task = Task {
            defer { resolutionTask = nil }
            let snapshot = try await Self.makeSnapshot(
                candidates: discoverCandidates(),
                sourceID: sourceID,
                preferenceStore: preferenceStore,
            )
            cachedState = snapshot
            AppLogger.debug("Host 解析完成，候选=\(snapshot.candidates.count)", category: "Source.Host")
            return snapshot
        }
        resolutionTask = task
        return try await SourceSharedWait.value(of: task)
    }

    /// 用发现结果构建快照：读取已选偏好，仍有效则沿用，否则固定候选第一个。
    private static func makeSnapshot(
        candidates: [SourceHostCandidate],
        sourceID: ComicSourceID,
        preferenceStore: SourceHostPreferenceStore,
    ) async throws -> SourceHostSelectionSnapshot {
        let preferred = await preferenceStore.selectedBaseURL(for: sourceID)
        return try SourceHostSelectionResolver.snapshot(
            candidates: candidates,
            preferredBaseURL: preferred,
        )
    }
}

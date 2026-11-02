import Foundation
import Observation

/// 管理来源设置页里的 Host 快照与切换。
///
/// 只做「读取候选／提交选择」两件事；真正的网络发现、切换后使旧 Session
/// 失效、失败保留原环境等语义都由来源 Services 保证。页面级 owner，随设置页销毁取消
/// 在途等待（已接受的来源操作继续执行）。
///
/// 所有入口都要求没有在途操作，因此不需要额外代次校验。
@MainActor
@Observable
final class SourceHostSettingsModel {
    /// 已确认的候选列表与实际绑定地址；首次加载完成前为 `nil`。
    private(set) var snapshot: SourceHostSelectionSnapshot?

    /// 操作互斥，用一个状态表达，避免多个 Bool 产生不可能的组合。
    private enum Operation {
        case loading, selecting
    }

    private var operation: Operation?

    var isLoading: Bool {
        operation == .loading
    }

    /// 展示给用户的失败提示；与 `snapshot` 无关，成功后清空。
    private(set) var errorMessage: String?

    /// 是否有操作在途；用于禁用选择入口。
    var isBusy: Bool {
        operation != nil
    }

    @ObservationIgnored
    private let loadSnapshot: @Sendable () async throws -> SourceHostSelectionSnapshot

    @ObservationIgnored
    private let selectHost: @Sendable (URL) async throws -> SourceHostSelectionSnapshot

    @ObservationIgnored
    private var task: Task<Void, Never>?

    init(
        loadSnapshot: @escaping @Sendable () async throws -> SourceHostSelectionSnapshot,
        selectHost: @escaping @Sendable (URL) async throws -> SourceHostSelectionSnapshot,
    ) {
        self.loadSnapshot = loadSnapshot
        self.selectHost = selectHost
    }

    /// 用来源 Services 的线路能力创建模型。
    ///
    /// `onHostSelected` 在切换成功后执行（例如禁漫刷新图源设置），失败时不执行。
    convenience init(
        services: some SourceHostSettingsProviding,
        onHostSelected: (@Sendable () async -> Void)? = nil,
    ) {
        self.init(
            loadSnapshot: { try await services.hostSelectionSnapshot() },
            selectHost: { baseURL in
                let snapshot = try await services.selectHost(baseURL: baseURL)
                await onHostSelected?()
                return snapshot
            },
        )
    }

    deinit {
        task?.cancel()
    }

    /// 首次展示时加载候选；已加载、加载中或已有在途操作时不重复请求。
    func loadIfNeeded() {
        guard snapshot == nil, !isBusy else {
            return
        }

        run(.loading, loadSnapshot)
    }

    /// 加载失败后重新请求候选。
    func retry() {
        guard !isBusy else {
            return
        }

        run(.loading, loadSnapshot)
    }

    /// 提交用户选择；成功后 active 切到新地址，失败保留原快照并提示。
    func select(_ baseURL: URL) {
        guard snapshot?.activeBaseURL != baseURL, !isBusy else {
            return
        }

        let selectHost = selectHost
        run(.selecting) {
            try await selectHost(baseURL)
        }
    }

    /// 运行一次操作；完成后在 MainActor 上统一复位在途标记，并按结果更新状态。
    private func run(
        _ kind: Operation,
        _ request: @escaping @Sendable () async throws -> SourceHostSelectionSnapshot,
    ) {
        operation = kind
        errorMessage = nil
        task = Task { [weak self] in
            let outcome: Result<SourceHostSelectionSnapshot, any Error>
            do {
                outcome = try await .success(request())
            } catch {
                outcome = .failure(error)
            }

            guard let self else {
                return
            }

            switch outcome {
            case let .success(snapshot):
                self.snapshot = snapshot

            case .failure(is CancellationError):
                break

            case .failure:
                errorMessage = "服务器线路操作失败，请重试"
            }

            operation = nil
            task = nil
        }
    }
}

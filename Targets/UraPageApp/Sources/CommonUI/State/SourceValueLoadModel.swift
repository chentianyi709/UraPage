import Observation

/// 一次性加载的页面级 owner；详情、列表、分类目录共用，成功状态直接持有结果。
/// 切 Tab 不取消，页面状态销毁时取消请求；空数组是成功结果，空态由展示层决定。
///
/// 请求期间任务不强持有本对象，只有写回状态时才短暂访问，避免离开页面后仍保留整页资源。
@MainActor
@Observable
final class SourceValueLoadModel<Value: Sendable> {
    private(set) var loadState: InitialValueLoadState<Value> = .idle

    /// 已加载的值；供标题和工具栏读取，不额外保存第二份状态。
    var value: Value? {
        guard case let .loaded(value) = loadState else { return nil }

        return value
    }

    /// 不携带结果的展示阶段，供首屏四槽组件使用；不额外存储第二份状态。
    var phase: InitialLoadState<SourceLoadDisplayError> {
        switch loadState {
        case .idle: .idle
        case .loading: .loading
        case .loaded: .loaded
        case let .failed(error): .failed(error)
        }
    }

    @ObservationIgnored private let loadValue: @Sendable () async throws -> Value
    @ObservationIgnored private let logCategory: String
    @ObservationIgnored private var loadTask: Task<Void, Never>?

    init(
        logCategory: String,
        loadValue: @escaping @Sendable () async throws -> Value,
    ) {
        self.logCategory = logCategory
        self.loadValue = loadValue
    }

    deinit {
        loadTask?.cancel()
    }

    /// 首次展示时加载；已失败的请求仅由页面上的重试动作重新发起。
    func loadIfNeeded() {
        guard case .idle = loadState else { return }

        startLoading()
    }

    func retry() {
        guard case .failed = loadState else { return }

        startLoading()
    }

    private func startLoading() {
        loadState = .loading

        let loadValue = loadValue
        // 加载与结果映射通常包含解码和数组整理；任务不读写 UI 状态时放到通用执行器。
        loadTask = Task { @concurrent [weak self] in
            do {
                let value = try await loadValue()
                try Task.checkCancellation()
                await self?.finishLoading(with: value)
            } catch is CancellationError {
                await self?.finishLoadingCancellation()
            } catch {
                await self?.finishLoading(with: error)
            }
        }
    }

    private func finishLoadingCancellation() {
        loadTask = nil
        // 页面销毁的取消已被 weak self 挡掉；能写回的是来源内部取消（如 Host 切换），
        // 按不可用处理并保留重试入口，避免页面停在骨架或空白。
        loadState = .failed(.unavailable)
        AppLogger.warning("加载被来源取消，展示为不可用", category: logCategory)
    }

    private func finishLoading(with value: Value) {
        loadTask = nil
        loadState = .loaded(value)
    }

    private func finishLoading(with error: any Error) {
        loadTask = nil
        let displayError = SourceLoadDisplayError(error)
        loadState = .failed(displayError)
        AppLogger.warning("加载失败（展示错误=\(displayError)）", category: logCategory)
    }
}

/// 列表展示投影；未就绪时没有条目，错误与加载阶段仍由 `loadState` 明确区分。
extension SourceValueLoadModel where Value: RangeReplaceableCollection {
    var items: Value {
        value ?? Value()
    }
}

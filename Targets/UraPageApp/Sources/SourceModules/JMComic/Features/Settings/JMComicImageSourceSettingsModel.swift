import Observation

/// 禁漫来源设置里的图源状态 owner：读取候选、提交切换、失败回滚。
///
/// 图源来自远程 Setting（Host 变化会重新取），因此这里只保存一份快照；
/// 选择立即交给 `JMComicServices`（由 Client 串行排队并替换 Setting），
/// 提交期间控件显示待确认值，失败则回到已确认值并给出提示。
@MainActor
@Observable
final class JMComicImageSourceSettingsModel {
    private(set) var snapshot: JMComicImageSourceSelectionSnapshot?
    private(set) var isLoading = false
    private(set) var isUpdating = false
    private(set) var errorMessage: String?

    /// 加载或提交期间为真：页面用它禁用其它同样会改动 Client 状态的设置。
    var isBusy: Bool {
        isLoading || isUpdating
    }

    /// 选择控件应立即显示的值：提交期间显示待确认选择，失败后回到已确认值。
    var displayedKey: Int? {
        pendingKey ?? snapshot?.selectedKey
    }

    @ObservationIgnored private let services: JMComicServices
    @ObservationIgnored private let invalidateImageRequests: @MainActor () -> Void
    /// 待确认图源不参与观察，必须与 `isLoading`／`isUpdating` 同批变更；
    /// 否则 `displayedKey` 的变化不会触发界面刷新。
    @ObservationIgnored private var pendingKey: Int?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var generation = 0

    /// 持有禁漫公开服务；图源切换成功后通过公共入口取消浏览图片的在途请求。
    init(
        services: JMComicServices,
        invalidateImageRequests: @escaping @MainActor () -> Void,
    ) {
        self.services = services
        self.invalidateImageRequests = invalidateImageRequests
    }

    // 关闭设置弹窗不取消在途操作：读取快照会在后台静默完成，已提交的图源切换由
    // Client 继续执行，成功后仍需通过失效回调取消浏览图片的在途请求。

    /// 尚未加载快照时开始读取。
    func loadIfNeeded() {
        guard snapshot == nil, !isLoading, task == nil else {
            return
        }

        startLoading()
    }

    /// Host 变更成功后重新读取图源；读取失败的重试也走同一入口。
    func reload() {
        startLoading()
    }

    /// 提交选择；失败时保留旧快照并让控件回到旧值。
    func select(_ key: Int) {
        guard snapshot?.selectedKey != key, !isUpdating else {
            return
        }

        pendingKey = key
        startOperation(isUpdating: true) { [services] in
            try await services.selectImageSource(key)
        }
    }

    /// 读取图源快照；先清除旧 Host 的展示值，失败时留下新环境的重试入口。
    private func startLoading() {
        snapshot = nil
        pendingKey = nil
        startOperation(isUpdating: false) { [services] in
            try await services.imageSourceSelectionSnapshot()
        }
    }

    /// 运行一次带代次校验的异步操作，迟到的旧结果不覆盖新状态。
    private func startOperation(
        isUpdating: Bool,
        operation: @escaping @Sendable () async throws -> JMComicImageSourceSelectionSnapshot,
    ) {
        generation += 1
        let operationGeneration = generation
        // 更新可能在弹窗关闭后才完成；提前取出失效回调，任务不再依赖模型仍然存活。
        let onImageEnvironmentChange: (@MainActor () -> Void)? = isUpdating ? invalidateImageRequests : nil

        task?.cancel()
        isLoading = !isUpdating
        self.isUpdating = isUpdating
        errorMessage = nil

        task = Task { [weak self] in
            do {
                let snapshot = try await operation()
                try Task.checkCancellation()

                // 切换已经生效，即使设置页已关闭也要让浏览图片改用新环境。
                if let onImageEnvironmentChange {
                    onImageEnvironmentChange()
                }

                guard let self, operationGeneration == generation else {
                    return
                }

                self.snapshot = snapshot
                pendingKey = nil
                isLoading = false
                self.isUpdating = false
                task = nil
            } catch {
                guard let self, operationGeneration == generation else {
                    return
                }

                isLoading = false
                self.isUpdating = false
                pendingKey = nil
                errorMessage = isUpdating ? "图源切换失败，请重试" : "图源列表加载失败，请重试"
                task = nil
            }
        }
    }
}

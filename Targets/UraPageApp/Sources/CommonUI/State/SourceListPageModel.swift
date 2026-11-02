import Observation

/// 来源列表页的页面级状态与数据加载链。
///
/// 数据链「前提菜单 → 列表首屏」的每个菜单请求各跑在自己的任务里；任务只在写回状态时短暂引用本对象，
/// **等待期间不持有**，因此页面状态被销毁（二级页 pop、切源替换体验）时本对象立即释放、
/// `deinit` 取消在途请求；切 Tab、被二级页覆盖时页面状态仍在，链会继续跑完（回到页面即为已加载内容）。
@MainActor
@Observable
final class SourceListPageModel<Query: Hashable & Sendable, Cursor: Sendable> {
    /// 当前查询；筛选选择与“前提菜单”的数据都会更新它。
    private(set) var query: Query

    /// 远端菜单项（按菜单在 `menus` 中的下标）与失败位置对应的展示错误。
    ///
    /// 不额外保存“正在加载”标记：该位置是否显示进度由「远端菜单还没有数据且未失败」推导，
    /// 否则被取消的旧加载收尾时会清掉标记，让仍在飞的加载期间该位置变成空白。
    private(set) var remoteMenuItems: [Int: [SelectionMenuItem]] = [:]
    private(set) var failedMenuErrors: [Int: SourceLoadDisplayError] = [:]

    /// 分页模型；页面状态销毁时一并释放（其在途首屏请求由自身 `deinit` 取消）。
    let paging: ComicPagingModel<Query, Cursor>

    @ObservationIgnored let descriptor: SourceListPageDescriptor<Query, Cursor>
    @ObservationIgnored private var menuTasks: [Int: Task<Void, Never>] = [:]

    /// 首屏响应里顺带产出的筛选菜单项（按菜单 id）；声明 `.firstPage` 来源的菜单读它。
    private let firstPageMenuItems = FirstPageMenuItemsBox()

    /// 已应用的外部筛选请求序号；同一序号只应用一次。
    ///
    /// 参与观察：应用后页面要重算“是否还在等筛选请求”，才能把列表放进视图树。
    private var appliedFilterToken: Int?

    init(descriptor: SourceListPageDescriptor<Query, Cursor>) {
        self.descriptor = descriptor
        query = descriptor.query

        // 首屏菜单字典按菜单 id 定位，只允许出现声明为 `.firstPage` 的 id。
        // 来源拼错 key 时菜单会一直不可用（看起来像网络失败），因此 Debug 直接暴露。
        let firstPageMenuIDs = Set(descriptor.menus.compactMap { menu -> String? in
            guard case .firstPage = menu.source else { return nil }

            return menu.id
        })

        // 分页执行器只拿列表切片；首屏顺带产出的菜单项在这里接住（筛选菜单属于本模型）。
        // 闭包捕获盒子而不是 `self`：初始化期还不能引用自身。
        let firstPageMenuItems = firstPageMenuItems
        paging = ComicPagingModel { query, cursor in
            let load = try await descriptor.loadPage(query, cursor)
            // 与分页器复用同一个任务取消边界，旧查询不能回填当前菜单。
            try Task.checkCancellation()
            // 首屏顺带产出的菜单（分类树）与查询无关：首次写入后保留，
            // 切换筛选不再清空重载，只在响应确实带回菜单项时更新。
            if cursor == nil, !load.menuItems.isEmpty {
                let unknownIDs = Set(load.menuItems.keys).subtracting(firstPageMenuIDs)
                if !unknownIDs.isEmpty {
                    assertionFailure("首屏菜单 key 不属于任何 .firstPage 菜单：\(unknownIDs.sorted())")
                    AppLogger.warning(
                        "首屏菜单 key 不属于任何 .firstPage 菜单，keys=\(unknownIDs.sorted())",
                        category: "List.Menu",
                    )
                }

                firstPageMenuItems.value = load.menuItems
            }

            return load.slice
        }
    }

    deinit {
        for task in menuTasks.values {
            task.cancel()
        }
    }

    // MARK: - 展示派生

    /// 还有未应用的外部筛选请求：此时不把列表放进视图树。
    ///
    /// 列表视图出现时会立刻用当前查询请求首屏，而页面应用筛选在 `onAppear`（晚于子视图）；
    /// 若不等待，跳转目标页会先用默认查询请求一次再按筛选重载。未带筛选请求时恒为 `false`。
    func isWaitingForFilterRequest(_ request: SourceListFilterRequest?) -> Bool {
        guard let request else {
            return false
        }

        return request.token != appliedFilterToken
    }

    /// 列表数据依赖的菜单尚未拿到可用数据；此时不请求列表（页面显示等待骨架）。
    var isWaitingForPrerequisiteMenu: Bool {
        descriptor.menus.enumerated().contains { index, menu in
            menu.makeInitialQuery != nil && remoteMenuItems[index] == nil && failedMenuErrors[index] == nil
        }
    }

    /// 前提菜单获取失败时的展示文案；`nil` 表示没有失败，正文按列表失败样式提示。
    var prerequisiteMenuFailureMessage: String? {
        for (index, menu) in descriptor.menus.enumerated() {
            guard menu.makeInitialQuery != nil, let displayError = failedMenuErrors[index] else { continue }

            return displayError.message
        }

        return nil
    }

    /// 该菜单位置当前的展示项；`nil` 表示还没有可用数据。
    ///
    /// 固定菜单直接用声明值；远端菜单用自己请求的结果；首屏提供的菜单读列表首屏结果。
    func menuItems(at index: Int) -> [SelectionMenuItem]? {
        switch descriptor.menus[index].source {
        case let .fixed(items):
            items

        case .remote:
            remoteMenuItems[index]

        case .firstPage:
            firstPageMenuItems.value[descriptor.menus[index].id]
        }
    }

    /// 该菜单当前的数据不可用错误；`nil` 表示可用或仍在加载。
    ///
    /// 首屏提供的菜单跟随列表首屏的**首次成功结果**：首屏成功后菜单即固定，之后切换筛选
    /// 导致列表失败也不影响菜单；首屏失败且尚无菜单数据时该位置变成重试按钮。
    /// 首屏成功但没有带回该菜单的数据时同样按不可用处理。重试等于重新加载首屏。
    func menuFailure(at index: Int) -> SourceLoadDisplayError? {
        switch descriptor.menus[index].source {
        case .fixed:
            return nil

        case .remote:
            return failedMenuErrors[index]

        case .firstPage:
            // 已有菜单数据时保持可用：列表失败由正文表达，工具栏不再变成重试按钮。
            guard menuItems(at: index) == nil else {
                return nil
            }

            switch paging.loadState {
            case let .failed(displayError):
                return displayError

            // 首屏已成功但响应没有带回该菜单：继续显示进度会永久转圈，
            // 因此按“数据不可用”处理，让工具栏保留与远端菜单一致的重试入口。
            case .loaded:
                return .unavailable

            case .idle, .loading:
                return nil
            }
        }
    }

    /// 菜单还没有数据且未失败：该菜单位置显示进度，而不是空白（首次加载、切回时的重新加载）。
    func isAwaitingMenuData(at index: Int) -> Bool {
        menuItems(at: index) == nil && menuFailure(at: index) == nil
    }

    // MARK: - 数据链

    /// 首次展示时启动需要接口的菜单加载；幂等（已加载、已失败、正在加载都不重开）。
    func startMenuLoadingIfNeeded() {
        for index in descriptor.menus.indices {
            loadRemoteMenuIfNeeded(at: index)
        }
    }

    /// 选择筛选项：只产生新查询，列表按新查询重新加载由页面驱动。
    func select(selectionID: String, inMenuAt index: Int) {
        query = descriptor.menus[index].makeQuery(query, selectionID)
    }

    /// 应用外部筛选请求（首页分区跳转等）；同一序号只应用一次。
    ///
    /// 请求里的多条菜单选择在同一次查询变更里全部应用：列表只按最终查询重新加载一次，
    /// 菜单数据不受影响。结果与当前查询相同时什么都不做，保留已加载数据与滚动位置。
    func applyFilterRequestIfNeeded(_ request: SourceListFilterRequest?) {
        guard let request, request.token != appliedFilterToken else {
            return
        }

        appliedFilterToken = request.token
        var nextQuery = query

        for selection in request.selections {
            guard let menu = descriptor.menus.first(where: { $0.id == selection.menuID }) else {
                // 请求由来源代码构造：id 拼错会让列表按缺少该条件的查询加载，
                // 用户看到错误结果而不是错误提示。Debug 直接暴露，Release 保持跳过。
                assertionFailure(
                    "外部筛选的菜单不存在：id=\(selection.menuID)，现有=\(descriptor.menus.map(\.id))",
                )
                AppLogger.warning(
                    "外部筛选的菜单不存在，id=\(selection.menuID)，菜单数=\(descriptor.menus.count)",
                    category: "List.Menu",
                )
                continue
            }

            nextQuery = menu.makeQuery(nextQuery, selection.selectionID)
        }

        guard nextQuery != query else {
            return
        }

        query = nextQuery
    }

    /// 重新获取一个菜单的数据（工具栏重试按钮与正文失败态共用）。
    ///
    /// 首屏提供的菜单没有自己的请求：它的重试等于重新加载列表首屏（成功后菜单项重新写入）。
    func retryMenu(at index: Int) {
        switch descriptor.menus[index].source {
        case .fixed:
            return

        case .remote:
            remoteMenuItems[index] = nil
            failedMenuErrors[index] = nil
            loadRemoteMenuIfNeeded(at: index)

        case .firstPage:
            paging.reload(query: query)
        }
    }

    /// 重试失败的前提菜单（正文失败态的「重新加载」按钮）。
    func retryPrerequisiteMenu() {
        for (index, menu) in descriptor.menus.enumerated()
            where menu.makeInitialQuery != nil && failedMenuErrors[index] != nil {
            retryMenu(at: index)
        }
    }

    /// 启动一个远端菜单的加载。
    ///
    /// 任务里只在等待之外写状态：等待期间不持有本对象，页面状态销毁时 `deinit` 才能立刻取消请求。
    private func loadRemoteMenuIfNeeded(at index: Int) {
        let menu = descriptor.menus[index]

        guard case let .remote(remoteItems) = menu.source,
              remoteMenuItems[index] == nil,
              failedMenuErrors[index] == nil,
              menuTasks[index] == nil
        else {
            return
        }

        menuTasks[index] = Task { [weak self] in
            do {
                let items = try await remoteItems()
                self?.applyRemoteMenuItems(items, for: menu, at: index)
            } catch is CancellationError {
                // 页面销毁时 weak self 已为 nil，不会写状态；能写回的是来源内部取消
                // （如 Host 切换），按不可用处理并清掉任务，否则该位置会永久转圈。
                self?.applyRemoteMenuFailure(.unavailable, at: index)
            } catch {
                self?.applyRemoteMenuFailure(SourceLoadDisplayError(error), at: index)
            }
        }
    }

    /// 写回菜单数据；属于列表前提的菜单会先补全查询，再请求列表首屏。
    private func applyRemoteMenuItems(
        _ items: [SelectionMenuItem],
        for menu: SourceToolbarMenu<Query>,
        at index: Int,
    ) {
        menuTasks[index] = nil

        if let makeInitialQuery = menu.makeInitialQuery {
            guard let completedQuery = makeInitialQuery(items, query) else {
                // 本次结果没有可用数据：按不可用处理，正文与工具栏都保留重试入口。
                failedMenuErrors[index] = .unavailable
                AppLogger.warning(
                    "远端菜单结果不可用（缺少可作为列表前提的数据），位置=\(index)，count=\(items.count)",
                    category: "List.Menu",
                )
                return
            }

            query = completedQuery
        }

        remoteMenuItems[index] = items

        startListIfPrerequisiteMenuIsReady()
    }

    /// 写回菜单失败：该位置变成重试按钮，正文按失败态提示（前提菜单失败时）。
    private func applyRemoteMenuFailure(_ displayError: SourceLoadDisplayError, at index: Int) {
        menuTasks[index] = nil

        failedMenuErrors[index] = displayError
        AppLogger.warning(
            "远端菜单加载失败，位置=\(index)（展示错误=\(displayError)）",
            category: "List.Menu",
        )
    }

    /// 前提菜单数据就绪（或没有前提菜单）时请求列表首屏；页面不可见时同样请求。
    private func startListIfPrerequisiteMenuIsReady() {
        guard !isWaitingForPrerequisiteMenu else {
            return
        }

        paging.loadIfNeeded(query: query)
    }
}

/// 承载「列表首屏顺带产出的筛选菜单项」的引用盒子（页面级 owner 私有）。
///
/// 分页执行器不感知筛选菜单，菜单数据因此不进入它；而分页器的加载闭包在初始化期就要建立，
/// 那时还不能捕获页面模型自身，所以先建盒子、由闭包捕获盒子，页面模型再读它。
@MainActor
@Observable
private final class FirstPageMenuItemsBox {
    var value: [String: [SelectionMenuItem]] = [:]
}

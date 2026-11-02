import Foundation
import Observation
import SwiftUI

/// App Shell：持有唯一的当前来源体验，并执行切源事务（§9.2）。
///
/// 启动时在 `init` 内同步构建默认来源的体验（不触网、无 IO），首帧即展示来源 TabBar，
/// 不存在"先空白再出现内容"的过渡；只有切源释放旧体验的期间会短暂进入无体验状态。
@MainActor
@Observable
final class AppShellModel: SourcePresentationHandling, SourceImageRequestInvalidationHandling {
    private let host: AppSourceHost

    /// 记录用户最后选择的来源及列表顺序；操作成功后立即落盘，不依赖退出回调。
    private let sourceSelection = SourceSelectionStore()

    /// 来源切换弹窗展示的来源清单；按用户排序恢复，未排序的新增来源按注册顺序追加。
    private(set) var descriptors: [SourceDescriptor]

    /// 各来源的轻量导航状态；切源后保留，用于恢复 Tab。
    private var navigations: [ComicSourceID: SourceNavigationState] = [:]

    /// 关闭旧体验期间只更新目标，由正在执行的切源流程统一提交最后一次选择。
    @ObservationIgnored private var requestedSourceID: ComicSourceID

    /// 正在切换来源：切换中禁用弹窗内的来源行，避免重复提交。
    private(set) var isSwitchingSource = false

    /// 当前展示的 App 级 Sheet；只保留一个，新的呈现请求在已有弹窗时被忽略（§8.3）。
    private(set) var presentedSheet: AppSheetRoute?

    /// 当前激活的来源体验；启动时构建，切源释放旧体验期间为 `nil`。
    private(set) var activeExperience: ActiveSourceExperience?

    init(host: AppSourceHost) {
        self.host = host
        let savedOrder = sourceSelection.sourceOrder()
        let sourceRanks = Dictionary(uniqueKeysWithValues: savedOrder.enumerated().map { (
            $0.element,
            $0.offset,
        ) })
        // 未排序的新来源按注册顺序追加；显式复合键，不依赖 `sorted` 的稳定性。
        descriptors = host.descriptors
            .enumerated()
            .sorted { lhs, rhs in
                let lhsRank = sourceRanks[lhs.element.sourceID] ?? savedOrder.count + lhs.offset
                let rhsRank = sourceRanks[rhs.element.sourceID] ?? savedOrder.count + rhs.offset
                return lhsRank < rhsRank
            }
            .map(\.element)

        // 恢复上次使用的来源；首次启动时使用注册顺序第一个（默认来源）。
        let storedSourceID = sourceSelection.selectedSource()
        let sourceID = storedSourceID ?? host.defaultSourceID
        requestedSourceID = sourceID
        if storedSourceID != sourceID {
            sourceSelection.save(sourceID)
        }

        AppLogger.debug(
            "启动来源，source=\(sourceID.rawValue)，缓存值=\(storedSourceID?.rawValue ?? "无")，已写回=\(storedSourceID != sourceID)",
            category: "App.Shell",
        )

        activeExperience = host.makeExperience(sourceID: sourceID, navigation: navigation(for: sourceID))
    }

    /// 展示一个 App 级 Sheet；由调用方给出 route（含它需要的上下文），已有弹窗时忽略新请求，避免叠层呈现。
    ///
    /// "哪个来源的设置"这类上下文由**发起方**明确给出（来源页面知道自己属于哪个来源），
    /// 因此 Shell 不做隐式的"当前来源"解析：跨来源 push 的场景也不会把设置开成别的来源。
    func presentSheet(_ route: AppSheetRoute) {
        guard presentedSheet == nil else {
            return
        }

        presentedSheet = route
    }

    func presentSourceSelection() {
        presentSheet(.sourceSelection)
    }

    /// 只更新展示顺序，不切换来源，也不改变首次启动的默认来源。
    func moveSources(fromOffsets offsets: IndexSet, toOffset destination: Int) {
        guard !isSwitchingSource else {
            return
        }

        descriptors.move(fromOffsets: offsets, toOffset: destination)
        sourceSelection.saveSourceOrder(descriptors.map(\.sourceID))
    }

    func presentSourceSettings(for sourceID: ComicSourceID) {
        presentSheet(.sourceSettings(sourceID))
    }

    /// 来源图片环境切换成功后，取消当前来源体验仍在途的普通图片请求。
    ///
    /// 只作用于当前激活体验：设置弹窗里的图片工作域不承载浏览页面，缓存与已显示图片也不受影响。
    /// 关闭弹窗后仍在加载的 `ComicImageView` 会按新环境立即重新请求。
    func invalidateBrowsingImageRequests(for sourceID: ComicSourceID) {
        guard let experience = activeExperience, experience.sourceID == sourceID else {
            return
        }

        experience.state.resources.browsingImageScope.invalidateInFlight()
    }

    /// 关闭当前 App 级 Sheet；没有展示内容时保持幂等。
    func dismissSheet() {
        presentedSheet = nil
    }

    /// 切换到本源 Tab 的根页面：选中该 Tab 并清空它的栈。
    ///
    /// 供来源页面做「跳到另一个 Tab 的列表页」这类站内跳转（与旧版 `selectRoot` 同义）。
    /// 传入其他来源的 Tab 属于装配错误，不做静默忽略；没有激活体验时（切源瞬间）不做事。
    func selectRoot(of tab: SourceTab) {
        guard let experience = activeExperience else {
            return
        }
        guard tab.sourceID == experience.sourceID else {
            preconditionFailure("体验收到其他来源的 Tab：\(tab)，当前来源=\(experience.sourceID.rawValue)")
        }

        experience.navigation.selectedTab = tab
        experience.navigation.router(for: tab).popToRoot()
        AppLogger.debug("切换到根页面，tab=\(tab)", category: "Navigation")
    }

    /// 切换到指定来源并关闭弹窗；释放与提交统一由 `activate` 处理。
    func switchSource(to sourceID: ComicSourceID) async {
        await activate(sourceID)
        dismissSheet()
    }

    /// 切换来源；已激活同一来源时不重复重建。
    /// 切源期间再次调用只更新目标并立即返回，不代表目标体验已经激活。
    func activate(_ sourceID: ComicSourceID) async {
        requestedSourceID = sourceID
        guard !isSwitchingSource else {
            return
        }
        guard activeExperience?.sourceID != sourceID else {
            return
        }

        isSwitchingSource = true
        defer { isSwitchingSource = false }

        // await 会让出 MainActor；期间的新选择不能另起关闭流程或提前创建体验。
        // 已开始的关闭必须完成，即使发起调用的页面 Task 被取消，也继续提交新体验。
        AppLogger.debug(
            "切源开始：\(activeExperience?.sourceID.rawValue ?? "无") → \(sourceID.rawValue)",
            category: "App.Shell",
        )
        let switchStart = ContinuousClock.now

        await releaseActiveExperience()

        // 读取最新目标后同步构建并提交，中间没有挂起点，不会被旧选择覆盖。
        let latestSourceID = requestedSourceID
        activeExperience = host.makeExperience(
            sourceID: latestSourceID,
            navigation: navigation(for: latestSourceID),
        )

        AppLogger.info(
            "切源完成：source=\(latestSourceID.rawValue)，耗时 \(AppLogger.milliseconds(switchStart.duration(to: .now)))",
            category: "App.Shell",
        )

        // 切换成功即保存，下次启动恢复本次选择（与旧版一致，不依赖退出回调）。
        sourceSelection.save(latestSourceID)
    }

    /// 先失效导航锚点并停止展示旧体验，最后关闭其独占资源（§9.2、§9.3）。
    private func releaseActiveExperience() async {
        guard let experience = activeExperience else {
            return
        }

        // Reader 仍有真实 Canvas 时完成最终采样和关闭，再移除体验视图。
        await experience.state.resources.readerSessions.close()

        // §9.2 第 3 步：使旧导航锚点失效，丢弃切源前发起、尚未落地的异步导航。
        experience.navigation.invalidateAnchors()

        // Reader 已完成关闭；移除旧体验后再释放页面状态与普通图片工作域。
        activeExperience = nil
        let releaseStart = ContinuousClock.now
        AppLogger.debug("关闭旧体验开始，source=\(experience.sourceID.rawValue)", category: "App.Shell")
        await experience.state.shutdown()
        AppLogger.debug(
            "关闭旧体验完成，source=\(experience.sourceID.rawValue)，耗时 \(AppLogger.milliseconds(releaseStart.duration(to: .now)))",
            category: "App.Shell",
        )
    }

    /// 返回该来源已有的轻量导航状态；首次激活时按来源默认 Tab 创建。
    private func navigation(for sourceID: ComicSourceID) -> SourceNavigationState {
        if let existing = navigations[sourceID] {
            return existing
        }

        let created = host.defaultNavigationState(for: sourceID)
        navigations[sourceID] = created
        return created
    }

    // MARK: - 导航定位

    /// 当前 Tab 的导航栈；切源释放旧体验的瞬间没有体验，因此可能为 `nil`。
    ///
    /// 只提供定位：push/pop 与锚点都由 `AppNavigator` 实现，这里不重复一套导航动作。
    var activeRouter: AppRouter? {
        guard let experience = activeExperience else {
            return nil
        }

        return experience.navigation.router(for: experience.navigation.selectedTab)
    }
}

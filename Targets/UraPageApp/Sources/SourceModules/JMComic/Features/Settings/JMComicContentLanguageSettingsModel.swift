import Observation

/// 禁漫「内容语言」设置 owner：提交语言并用新语言重新获取远程 Setting。
///
/// 切换语言会改变后续所有 GET 的 `lang` 参数，并需要重新请求 `/setting`；新 Setting 会带来
/// 新的图片 Host，因此成功后还要失效在途浏览图片请求。提交期间控件显示待确认值，失败由
/// Client 回滚偏好，这里回到已确认值并给出提示。
@MainActor
@Observable
final class JMComicContentLanguageSettingsModel {
    /// 已由远程 Setting 刷新确认的语言。
    private(set) var confirmedLanguage: JMComicContentLanguage
    private(set) var isUpdating = false
    private(set) var errorMessage: String?

    /// 选择控件应立即显示的值：提交期间显示待确认语言，失败后回到已确认值。
    var displayedLanguage: JMComicContentLanguage {
        pendingLanguage ?? confirmedLanguage
    }

    @ObservationIgnored private let services: JMComicServices
    @ObservationIgnored private let invalidateImageRequests: @MainActor () -> Void
    @ObservationIgnored private let onSettingUpdated: @MainActor () -> Void

    /// 待确认语言不参与观察，必须与 `isUpdating` 同批变更：提交时一起置位，
    /// 成功或失败时一起清空；否则 `displayedLanguage` 的变化不会触发界面刷新。
    @ObservationIgnored private var pendingLanguage: JMComicContentLanguage?

    /// 读取当前确认语言；`invalidateImageRequests` 在远程 Setting 刷新成功后调用，
    /// 取消按旧图片环境发起的在途请求；`onSettingUpdated` 用于刷新图源展示。
    init(
        services: JMComicServices,
        invalidateImageRequests: @escaping @MainActor () -> Void,
        onSettingUpdated: @escaping @MainActor () -> Void = {},
    ) {
        self.services = services
        self.invalidateImageRequests = invalidateImageRequests
        self.onSettingUpdated = onSettingUpdated
        confirmedLanguage = services.selectedContentLanguage()
    }

    /// 提交语言；失败时 Client 已回滚偏好，这里只需让控件回到已确认值并提示。
    func select(_ language: JMComicContentLanguage) {
        guard language != confirmedLanguage, !isUpdating else {
            return
        }

        pendingLanguage = language
        isUpdating = true
        errorMessage = nil

        // 切换成功会改变图片请求环境；提前取出回调，弹窗关闭后完成也要让浏览图片改用新环境。
        let services = services
        let invalidateImageRequests = invalidateImageRequests

        // 关闭设置弹窗不取消已提交的切换：请求入队后由 Client 继续完成。
        Task { [weak self] in
            do {
                try await services.selectContentLanguage(language)

                // 新 Setting 已替换，取消按旧 Host 发起的在途浏览图片请求并让它们重新请求。
                invalidateImageRequests()

                guard let self else { return }

                confirmedLanguage = language
                pendingLanguage = nil
                isUpdating = false
                onSettingUpdated()
            } catch {
                guard let self else { return }

                pendingLanguage = nil
                isUpdating = false
                errorMessage = "内容语言切换失败，请重试"
            }
        }
    }
}

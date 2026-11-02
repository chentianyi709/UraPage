import Foundation

/// 持有禁漫当前业务 Session、远程 Setting 与请求环境。
///
/// 准备与认证流程复用公共 Client 契约；本类型只负责禁漫的内容语言、远程图源切换，
/// 并为账号层和本源请求提供稳定 Client。
actor JMComicSourceClient: SourceAuthenticatedClient {
    let hostProvider: SourceHostProvider

    /// 统一保存并持久化禁漫来源本地行为偏好。
    let sourcePreferences = JMComicSourcePreferences()

    let clientState: SourceClientState<JMComicPreparedState>

    /// 串行执行 Host 变更与图源切换，并让读取等待在途变更结束。
    let hostOperations = SourceHostOperationRunner()

    /// 认证失效收口（公共入口）：判定 401 并通知账号 owner 清凭证、发布未登录。
    let authentication: SourceAuthenticationHandler

    @MainActor
    init(
        hostProvider: SourceHostProvider,
        access: JMComicAccountAccessStore,
    ) {
        self.hostProvider = hostProvider
        authentication = SourceAuthenticationHandler(access: access)

        // 捕获已初始化的依赖值与其他构造参数：既不引用尚未完成初始化的 self，也让准备闭包与属性共享同一实例。
        clientState = SourceClientState { [sourcePreferences] in
            try await JMComicSourceClient.makePreparedState(
                hostProvider: hostProvider,
                sourcePreferences: sourcePreferences,
                access: access,
            )
        }
    }

    /// 返回远程 Setting 已确认的图源候选、当前选择与实际图片 Host。
    func imageSourceSelectionSnapshot() async throws -> JMComicImageSourceSelectionSnapshot {
        // 图源切换与 Host 变更串行执行，读取前先等它们结束，避免展示变更中途的状态。
        try await hostOperations.waitForInFlight()
        return try await clientState.read { state in
            JMComicSourceClient.imageSourceSelectionSnapshot(from: state.setting)
        }
    }

    /// 返回禁漫 GET 请求当前使用的内容语言。
    nonisolated func selectedContentLanguage() -> JMComicContentLanguage {
        sourcePreferences.contentLanguage()
    }

    /// 保存内容语言并用新语言重新获取远程 Setting；与 Host 变更、图源切换串行执行。
    ///
    /// 语言偏好立即影响后续 GET 的 `lang` 参数；重新请求失败时回滚到原语言并抛错，
    /// 避免本地偏好与设置页确认值不一致。
    func selectContentLanguage(_ language: JMComicContentLanguage) async throws {
        try await hostOperations.enqueue {
            try await self.performContentLanguageSelection(language)
        }
    }

    /// 返回分类请求当前是否使用繁体分类参数。
    ///
    /// `nonisolated`：只读写 Sendable 的本地偏好，不需要 actor 串行（设置页因此可同步绑定）。
    nonisolated func selectedUsesTraditionalCategoryParameter() -> Bool {
        sourcePreferences.usesTraditionalCategoryParameter()
    }

    /// 保存分类参数转换偏好；不改变 Session 或其它接口。
    ///
    /// `nonisolated`：同读取，只动本地偏好。
    nonisolated func selectUsesTraditionalCategoryParameter(_ isEnabled: Bool) -> Bool {
        let current = sourcePreferences.usesTraditionalCategoryParameter()
        guard isEnabled != current else {
            return current
        }

        sourcePreferences.selectUsesTraditionalCategoryParameter(isEnabled)
        return isEnabled
    }

    /// 提交远程图源切换；与 Host 变更串行执行，关闭设置 Sheet 不取消已接受的操作。
    func selectImageSource(_ key: Int) async throws -> JMComicImageSourceSelectionSnapshot {
        try await hostOperations.enqueue {
            try await self.performImageSourceSelection(key)
        }
    }

    /// 在串行队列内请求 Setting、校验结果并提交新图源。
    ///
    /// 队列保证执行期间不会有 Host 变更使准备状态失效，因此这里直接使用当前准备状态。
    private func performImageSourceSelection(_ key: Int) async throws -> JMComicImageSourceSelectionSnapshot {
        let preparedState = try await clientState.preparedState()
        guard preparedState.setting.imageSources.contains(where: { $0.key == key }) else {
            throw JMComicAPIError.invalidSetting
        }
        guard key != preparedState.setting.selectedImageSourceKey else {
            return Self.imageSourceSelectionSnapshot(from: preparedState.setting)
        }

        // 用同一个 Session 请求目标图源的 Setting；图源切换只更新 Setting，不重建 Session。
        let setting = try await Self.fetchRemoteSetting(using: preparedState.session, imageSourceKey: key)
        Self.storeImageSourceKey(setting.selectedImageSourceKey)
        await clientState.replace(
            JMComicPreparedState(
                baseURL: preparedState.baseURL,
                session: preparedState.session,
                setting: setting,
            ),
        )
        return Self.imageSourceSelectionSnapshot(from: setting)
    }

    /// 在串行队列内用新语言重新请求 Setting，并替换当前准备状态。
    ///
    /// 先写入偏好让请求拦截器补上新的 `lang`；请求失败时回滚偏好，保持本地状态与设置页一致。
    private func performContentLanguageSelection(_ language: JMComicContentLanguage) async throws {
        let current = sourcePreferences.contentLanguage()
        guard language != current else { return }

        let preparedState = try await clientState.preparedState()
        sourcePreferences.selectContentLanguage(language)
        do {
            let setting = try await Self.fetchRemoteSetting(
                using: preparedState.session,
                imageSourceKey: preparedState.setting.selectedImageSourceKey,
            )
            // 语言切换复用同一 Session，只替换 Setting；图片 Host 以新 Setting 为准。
            Self.storeImageSourceKey(setting.selectedImageSourceKey)
            await clientState.replace(
                JMComicPreparedState(
                    baseURL: preparedState.baseURL,
                    session: preparedState.session,
                    setting: setting,
                ),
            )
        } catch {
            sourcePreferences.selectContentLanguage(current)
            throw error
        }
    }
}

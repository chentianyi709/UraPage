/// 保存同一批来源 Services 的公共协议视图，供真实跨来源 consumer 按 `sourceID` 查找。
///
/// 只在 composition root 创建一次；不保存 UI、账号 ViewModel、
/// 导航状态或页面数组，也不是动态插件 registry。
/// 来源自己的页面直接使用本源 Services，不通过 Catalog 查回自身。
struct SourceRuntimeCatalog: Sendable {
    private let runtimes: [ComicSourceID: any ComicSourceRuntime]

    /// 使用全部编译期来源的 Services 创建 Catalog。
    ///
    /// 拒绝重复 `sourceID`，并要求注册集合与 `ComicSourceID.allCases`
    /// 完全一致；缺少任一编译期来源即抛出 `missingSources`，
    /// 不以默认来源或可选能力兜底。
    init(runtimes: [any ComicSourceRuntime]) throws(RegistrationError) {
        var table: [ComicSourceID: any ComicSourceRuntime] = [:]
        for runtime in runtimes {
            guard table[runtime.sourceID] == nil else {
                throw .duplicateSource(runtime.sourceID)
            }

            table[runtime.sourceID] = runtime
        }

        let registered = Set(table.keys)
        let expected = Set(ComicSourceID.allCases)
        guard registered == expected else {
            throw .missingSources(expected.subtracting(registered))
        }

        self.runtimes = table
    }

    /// 返回指定来源的稳定能力视图。
    ///
    /// 初始化已保证覆盖全部 `allCases`，因此这里必定成功，
    /// 不提供 `try`、默认来源或可选返回。
    func runtime(for sourceID: ComicSourceID) -> any ComicSourceRuntime {
        guard let runtime = runtimes[sourceID] else {
            // 装配不变量：覆盖 allCases 后查找不应失败；失败代表内部错误。
            preconditionFailure("SourceRuntimeCatalog 缺少已注册来源: \(sourceID)")
        }

        return runtime
    }

    /// 装配阶段的来源注册错误；属于程序错误，不面向用户展示。
    enum RegistrationError: Error {
        /// 同一 `sourceID` 被注册多次。
        case duplicateSource(ComicSourceID)

        /// 缺少这些编译期来源的注册。
        case missingSources(Set<ComicSourceID>)
    }
}

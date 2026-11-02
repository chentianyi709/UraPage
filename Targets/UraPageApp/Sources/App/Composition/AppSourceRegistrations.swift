/// 来源注册表的唯一生成点。
///
/// 不写来源 `switch`：只列出各来源 Module，新增来源在 `ComicSourceID` 增加 case 后
/// 在这里补一行；缺来源由启动时 `SourceRuntimeCatalog` 的覆盖校验暴露。
/// 顺序即来源选择列表顺序，也是默认来源（第一个）。
@MainActor
enum AppSourceRegistrations {
    /// 组合根启动时调用一次：每个 Module 直接拥有自己的稳定 Services。
    static func make() -> [SourcePlugin] {
        [
            SourcePlugin(JMComicModule()),
            SourcePlugin(BikaModule()),
            SourcePlugin(ShenshiModule()),
        ]
    }
}

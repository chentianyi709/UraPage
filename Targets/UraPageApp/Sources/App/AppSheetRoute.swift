import Foundation

/// 由 App Shell 根节点统一展示的 typed Sheet（§8.3）。
///
/// App 级弹窗都走这一个 route：新增 App 级呈现时在这里加 case，
/// `AppShellView` 的 `sheet(item:)` 按 case 构造内容（来源相关的内容由对应来源 Module 提供）。
/// 页面自己的一次性弹窗（如评论、筛选）不走这里，用页面自己的 `@State` + `sheet` 即可。
nonisolated enum AppSheetRoute: Hashable, Sendable, Identifiable {
    /// 选择漫画源弹窗。
    case sourceSelection

    /// 指定来源的设置弹窗（漫画源设置／个人中心／通用设置）。
    ///
    /// 内容由该来源的 Module 提供（`SourceExperienceModule.makeSettingsSheet()`），
    /// App Shell 只负责在最外层呈现，因此跨来源 push 的页面同样能用。
    case sourceSettings(ComicSourceID)

    /// 用 route 自身作为稳定 presentation 标识。
    var id: Self {
        self
    }
}

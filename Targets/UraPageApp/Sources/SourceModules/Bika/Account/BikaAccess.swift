import SwiftUI

/// 哔咔访问规则：默认全部需要登录，只列出不需要登录的例外。
///
/// 规则在这里声明一次，页面不逐个判断：
/// - 二级页由 `BikaModule.defaultAccessRequirement` 引用本规则，公共 destination 边界统一套门禁；
///   离线页面由 `BikaRoute.usesLocalAssetsOnly` 自动放行。
/// - Tab 根由 `BikaRootView` 传入 `requirement(for:access:)`，其中只有书架例外。
///
/// 登录入口用公共登录表单（`SourceLoginView`），只绑定本源登录动作。
@MainActor
enum BikaAccess {
    /// 本源内容是否需要登录才能浏览（只有书架等本地内容例外）。
    ///
    /// 这个事实决定「个人中心」里退出登录后的收尾：需要登录的来源在退出后，
    /// 底层页面会原位变成未登录门禁，账号弹窗必须随之关闭，
    /// 而不是留在一个已经不可用的页面上（弹窗里还显示着刚清掉的资料）。
    static let requiresSignInToBrowse = true

    /// Tab 根的访问要求。
    ///
    /// 用排除法：新增 Tab 默认按需要登录处理，只有本地内容需要显式列出，
    /// 避免每加一个 Tab 都要回这里补一行。
    static func requirement(
        for tab: BikaTab,
        access: BikaAccountAccessStore,
    ) -> SourceAccessRequirement {
        tab == .library ? .publicContent : protectedRequirement(access: access)
    }

    /// 需要登录的页面：登录入口由门禁呈现，来源只提供登录页面。
    ///
    /// 这是本源在线内容的唯一门禁来源，Tab 与二级页共用。
    static func protectedRequirement(access: BikaAccountAccessStore) -> SourceAccessRequirement {
        .authenticated(
            access,
            login: SourceLoginContent {
                BikaLoginView(showsCancelButton: true)
            },
        )
    }
}

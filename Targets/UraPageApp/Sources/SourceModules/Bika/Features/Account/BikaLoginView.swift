import SwiftUI

/// 哔咔登录界面：公共 `SourceLoginView` 绑定本源登录动作（账号 + 密码）。
///
/// 由 `SourceAccessGate` 在门禁内呈现（`SourceLoginContent`），也被来源设置「个人中心」分页复用；
/// 登录成功后账号 owner 发布 `.authenticated`，门禁与账号页各自原位切换，本视图不负责关闭或跳转。
struct BikaLoginView: View {
    @Environment(\.bikaServices) private var services
    @Environment(\.sourceDescriptor) private var descriptor

    /// 是否显示「暂不登录」：门禁弹窗需要，内嵌在设置分页里不需要。
    let showsCancelButton: Bool

    var body: some View {
        SourceLoginView(
            sourceName: descriptor.displayName,
            logo: descriptor.logo,
            prompt: "登录后浏览哔咔内容",
            identifierKind: .username,
            showsCancelButton: showsCancelButton,
        ) { email, password in
            try await services.login(email: email, password: password)
        }
    }
}

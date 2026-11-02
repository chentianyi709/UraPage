import SwiftUI

/// 哔咔「个人中心」分页：公共 `SourceAccountPage` 骨架 + 本源登录入口与资料内容。
///
/// 哔咔内容需要登录才能浏览：退出登录后关闭承载本页的弹窗，让位给未登录门禁。
struct BikaAccountPage: View {
    @Environment(\.bikaServices) private var services
    @Environment(\.sourceDescriptor) private var descriptor

    var body: some View {
        SourceAccountPage(
            access: services.account.access,
            profile: services.account.profile,
            login: SourceLoginContent {
                BikaLoginView(showsCancelButton: false)
            },
            logout: { await services.logout() },
            closesSheetOnLogout: BikaAccess.requiresSignInToBrowse,
            logoutConfirmationMessage: "退出后需要重新登录才能浏览哔咔内容。",
        ) { profile in
            SourceAccountProfileHeader(displayName: profile.displayName, usesSurfaceBackground: true) {
                SourceLogoView(descriptor.logo, size: 104)
            }

            SourceAccountDetailRows(rows: [
                SourceAccountDetailRow(id: "email", title: "邮箱", value: profile.email),
                SourceAccountDetailRow(id: "account-id", title: "ID", value: profile.accountID),
            ])
        }
    }
}

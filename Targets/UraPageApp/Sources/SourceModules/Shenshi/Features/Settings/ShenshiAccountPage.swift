import SwiftUI

/// 绅士「个人中心」分页：公共 `SourceAccountPage` 骨架 + 本源登录入口与资料内容。
///
/// 绅士内容允许匿名浏览，因此退出登录后不关闭承载本页的弹窗。
struct ShenshiAccountPage: View {
    @Environment(\.shenshiServices) private var services
    @Environment(\.sourceDescriptor) private var descriptor

    var body: some View {
        SourceAccountPage(
            access: services.account.access,
            profile: services.account.profile,
            login: SourceLoginContent {
                SourceLoginView(
                    sourceName: descriptor.displayName,
                    logo: descriptor.logo,
                    prompt: "登录后查看绅士账号信息",
                    identifierKind: .username,
                ) { username, password in
                    try await services.login(username: username, password: password)
                }
            },
            logout: { await services.logout() },
        ) { profile in
            SourceAccountProfileHeader(displayName: profile.displayName, usesSurfaceBackground: true) {
                SourceLogoView(descriptor.logo, size: 104)
            }

            SourceAccountDetailRows(rows: [
                SourceAccountDetailRow(id: "username", title: "用户名", value: profile.username),
            ])
        }
    }
}

import SwiftUI

/// 禁漫「个人中心」分页：公共 `SourceAccountPage` 骨架 + 本源登录入口与资料内容。
///
/// 禁漫内容允许匿名浏览，因此退出登录后不关闭承载本页的弹窗。
struct JMComicAccountPage: View {
    @Environment(\.jmComicServices) private var services
    @Environment(\.sourceDescriptor) private var descriptor

    var body: some View {
        SourceAccountPage(
            access: services.account.access,
            profile: services.account.profile,
            login: SourceLoginContent {
                SourceLoginView(
                    sourceName: descriptor.displayName,
                    logo: descriptor.logo,
                    prompt: "登录后查看禁漫账号信息",
                    identifierKind: .username,
                ) { username, password in
                    try await services.login(username: username, password: password)
                }
            },
            logout: { await services.logout() },
        ) { profile in
            SourceAccountProfileHeader(displayName: profile.displayName, usesSurfaceBackground: false) {
                avatar(profile)
            }

            SourceAccountDetailRows(rows: [
                SourceAccountDetailRow(id: "username", title: "用户名", value: profile.username),
                SourceAccountDetailRow(id: "account-id", title: "ID", value: profile.accountID),
                SourceAccountDetailRow(id: "level", title: "等级", value: profile.levelText),
            ])
        }
    }

    /// 头像：无头像（或 locator 为空白）时显示同尺寸占位图标。
    @ContentBuilder
    private func avatar(_ profile: JMComicAccountProfile) -> some View {
        if let avatar = profile.avatar,
           avatar.locator.contains(where: { !$0.isWhitespace }) {
            ComicImageView(reference: avatar, targetSize: CGSize(width: 104, height: 104))
                .clipShape(.circle)
                .overlay {
                    Circle()
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                }
        } else {
            Circle()
                .fill(Color.surfaceElevated)
                .frame(width: 104, height: 104)
                .overlay {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 88))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(Color.iconSecondary)
                }
        }
    }
}

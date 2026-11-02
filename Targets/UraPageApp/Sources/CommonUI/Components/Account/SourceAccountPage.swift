import SwiftUI

/// 来源「个人中心」公共页面骨架：未登录＝登录表单，已登录＝资料与退出。
///
/// 三种状态的切换、检查态、检查失败重试、退出二次确认与失败提示、退出后是否关闭承载弹窗
/// 都在这里；来源只提供差异部分：登录入口内容、当前展示资料、按资料渲染的资料内容、退出动作。
/// 资料为 `nil` 表示本地账号状态不完整，回到登录表单让用户重新建立完整状态。
struct SourceAccountPage<Profile: Sendable, ProfileContent: View>: View {
    /// 访问事实 owner；页面据此在检查态／未登录／已登录／失败之间切换。
    let access: any SourceAccessProvider

    /// 当前展示资料；为 `nil` 时显示登录入口。
    let profile: Profile?

    /// 未登录时的登录入口（来源用公共 `SourceLoginView` 组装）。
    let login: SourceLoginContent

    /// 退出登录；返回是否成功，失败的提示由本页给出。
    let logout: () async -> Bool

    /// 退出成功后是否关闭承载本页的弹窗（内容需要登录才能浏览的来源，如哔咔）。
    let closesSheetOnLogout: Bool

    /// 退出确认弹窗的说明文案；默认与「账号信息」语义一致。
    let logoutConfirmationMessage: String

    /// 已登录时的资料内容（资料头 + 资料行），由来源按自己的资料类型渲染。
    @ContentBuilder let profileContent: (Profile) -> ProfileContent

    @Environment(\.dismiss) private var dismiss
    @State private var showsLogoutConfirmation = false
    @State private var isLoggingOut = false

    init(
        access: any SourceAccessProvider,
        profile: Profile?,
        login: SourceLoginContent,
        logout: @escaping () async -> Bool,
        closesSheetOnLogout: Bool = false,
        logoutConfirmationMessage: String = "退出后需要重新登录才能查看账号信息。",
        @ContentBuilder profileContent: @escaping (Profile) -> ProfileContent,
    ) {
        self.access = access
        self.profile = profile
        self.login = login
        self.logout = logout
        self.closesSheetOnLogout = closesSheetOnLogout
        self.logoutConfirmationMessage = logoutConfirmationMessage
        self.profileContent = profileContent
    }

    var body: some View {
        Group {
            switch access.current {
            case .checking:
                // 本机凭证读取，通常首帧内完成；期间不渲染内容，避免闪一下登录表单。
                Color.pageBackground

            case .authenticated:
                if let profile {
                    profileScreen(profile)
                } else {
                    loginScreen
                }

            case .unauthenticated:
                loginScreen

            case let .failed(failure):
                checkFailed(failure)
            }
        }
        .task {
            await access.ensureRestored()
        }
        .alert("退出登录？", isPresented: $showsLogoutConfirmation) {
            Button("取消", role: .cancel) {}

            Button("退出", role: .destructive) {
                performLogout()
            }
        } message: {
            Text(logoutConfirmationMessage)
        }
    }

    // MARK: - 未登录

    /// 登录入口；登录成功后账号 owner 发布已登录，本页原位切换成资料内容。
    private var loginScreen: some View {
        login.body()
    }

    // MARK: - 已登录

    /// 资料页：背景、资料内容与退出操作。
    private func profileScreen(_ profile: Profile) -> some View {
        ZStack {
            SourceLoginBackground()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 28) {
                    profileContent(profile)
                    logoutSection
                }
                .padding(.horizontal, 24)
                .padding(.top, 72)
                .padding(.bottom, 32)
            }
        }
    }

    /// 退出登录按钮与失败提示。
    private var logoutSection: some View {
        VStack(spacing: 12) {
            Button {
                showsLogoutConfirmation = true
            } label: {
                Group {
                    if isLoggingOut {
                        ProgressView()
                            .tint(Color.textOnPrimary)
                    } else {
                        Text("退出登录")
                            .font(.system(size: 17, weight: .semibold))
                    }
                }
                .foregroundStyle(Color.textOnPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.error)
                }
            }
            .buttonStyle(.plain)
            .disabled(isLoggingOut)
        }
    }

    /// 退出：清凭证与资料；需要登录才能浏览的来源在成功后关闭承载弹窗。
    private func performLogout() {
        guard !isLoggingOut else {
            return
        }

        isLoggingOut = true

        Task {
            let didLogout = await logout()
            isLoggingOut = false

            guard didLogout else {
                ToastCenter.shared.show("退出登录失败，请稍后重试", type: .error)
                return
            }

            ToastCenter.shared.show("已退出登录", type: .success)

            if closesSheetOnLogout {
                dismiss()
            }
        }
    }

    // MARK: - 检查失败

    /// 本机凭证状态异常：给重试入口，不伪装成未登录。
    private func checkFailed(_ failure: SourceAccessSnapshot.Failure) -> some View {
        LoadErrorView(
            title: "登录状态检查失败",
            message: failure.displayMessage,
            retryTitle: "重试",
            onRetry: {
                Task { await access.retryRestoration() }
            },
        )
    }
}

import Foundation
import SwiftUI

/// 受保护页面的访问门禁：登录状态**静默检查**，未登录时给出登录入口，通过后展示真实页面。
///
/// 页面自己不判断登录：门禁观察 `SourceAccessProvider.current`，登录、退出与凭证失效
/// 都会让内容在**原位**切换，不重新导航、不重复 push，也不改动导航栈。
/// 本源登录由门禁自己呈现（`SourceLoginContent`），因此本源内页面与跨来源 push 进来的页面都成立。
struct SourceAccessGate<Content: View>: View {
    @Environment(\.sourcePresentation) private var presentation
    @Environment(\.sourceDescriptor) private var descriptor

    /// 来源对当前页面的访问声明。
    let requirement: SourceAccessRequirement

    /// 正在展示的本源登录入口；`nil` 表示没有登录弹窗。
    @State private var login: LoginRequest?

    @ContentBuilder let content: () -> Content

    init(
        requirement: SourceAccessRequirement,
        @ContentBuilder content: @escaping () -> Content,
    ) {
        self.requirement = requirement
        self.content = content
    }

    var body: some View {
        switch requirement {
        case .publicContent:
            content()

        case let .authenticated(provider, loginContent):
            authenticatedContent(provider: provider, loginContent: loginContent)
        }
    }

    /// 读取账号事实并渲染对应状态；恢复任务由账号 owner 去重，多个页面同时等待只恢复一次。
    @ContentBuilder
    private func authenticatedContent(
        provider: any SourceAccessProvider,
        loginContent: SourceLoginContent,
    ) -> some View {
        let snapshot = provider.current

        Group {
            switch snapshot {
            case .checking:
                // 静默检查：不显示任何检查提示，也不提前渲染页面（避免登录状态未定就发出受保护请求）。
                //
                // TODO: 恢复本源账号目前是本机凭证读取，通常在首个渲染帧内完成，因此这里看不到内容；
                // 若某来源的恢复需要联网校验（网页验证等）导致长时间空白，
                // 待完成内容：超过阈值（约 200ms）后再显示检查提示。
                // 接入／替换条件：出现需要联网校验的账号恢复时。
                stateScreen {
                    EmptyView()
                }

            case .authenticated:
                content()

            case .unauthenticated:
                stateScreen {
                    loginRequired(loginContent)
                }

            case let .failed(failure):
                stateScreen {
                    checkFailed(failure, provider: provider)
                }
            }
        }
        .task {
            await provider.ensureRestored()
        }
        .sheet(item: $login) { request in
            request.content.body()
        }
        .onChange(of: snapshot) { _, newSnapshot in
            // 登录成功：关闭仍在展示的登录弹窗；其余状态变化不动用户已经打开的弹窗。
            if newSnapshot == .authenticated {
                login = nil
            }
        }
    }

    /// 未登录态：主按钮在门禁内呈现本源登录，次按钮保留切换来源的退路。
    private func loginRequired(_ loginContent: SourceLoginContent) -> some View {
        VStack(spacing: 16) {
            EmptyStateView(
                message: "当前页面需要登录\(descriptor.displayName)账号后才能查看",
                illustration: .login,
            )

            Button("登录") {
                login = LoginRequest(content: loginContent)
            }
            .buttonStyle(.borderedProminent)

            Button("切换漫画源") {
                presentation.presentSourceSelection()
            }
            .buttonStyle(.bordered)
        }
    }

    /// 检查失败态：本机凭证问题与在线校验失败给不同文案，避免把本地问题说成服务端响应无效。
    private func checkFailed(
        _ failure: SourceAccessSnapshot.Failure,
        provider: any SourceAccessProvider,
    ) -> some View {
        LoadErrorView(
            title: "登录状态检查失败",
            message: failureMessage(failure),
            retryTitle: "重试",
            onRetry: {
                Task { await provider.retryRestoration() }
            },
        )
    }

    /// 失败原因文案；与来源「个人中心」共用同一份映射。
    private func failureMessage(_ failure: SourceAccessSnapshot.Failure) -> String {
        failure.displayMessage
    }

    /// 门禁状态页：铺满可用区域、使用页面背景，并以来源展示名作导航栏标题。
    ///
    /// 状态页没有可滚动内容，`.inlineLarge` 会把大标题排到导航栏下方（看起来像页面内容）；
    /// 这里用标准 inline，标题固定显示在标题栏内，与返回按钮同一行。
    private func stateScreen(@ContentBuilder content: () -> some View) -> some View {
        ZStack {
            Color.pageBackground.ignoresSafeArea()

            content()
        }
        .navigationTitle(descriptor.displayName)
        .navigationBarTitleDisplayMode(.inline)
    }

    /// 一次登录呈现请求；用自身标识让重复点击可以重新呈现。
    private struct LoginRequest: Identifiable {
        let id = UUID()
        let content: SourceLoginContent
    }
}

extension SourceAccessSnapshot.Failure {
    /// 访问事实检查失败的展示文案：门禁状态页与来源「个人中心」共用。
    var displayMessage: String {
        switch self {
        case .credentialUnavailable:
            "无法读取本机登录状态，请重试"

        case let .checkFailed(error):
            SourceLoadDisplayError(error).message
        }
    }
}

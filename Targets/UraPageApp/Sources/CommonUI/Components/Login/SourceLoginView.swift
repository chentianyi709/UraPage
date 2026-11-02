import SwiftUI
import UIKit

/// 登录表单第一项凭证的输入语义（账号或邮箱）；不包含任何来源分支。
enum SourceLoginIdentifierKind {
    /// 账号／用户名（禁漫、绅士、哔咔）。
    case username

    /// 邮箱（表单支持的凭证类型；当前无来源使用）。
    case email

    /// 输入框标题与无障碍名称。
    var title: String {
        switch self {
        case .username: "账号"
        case .email: "邮箱"
        }
    }

    /// 向系统密码与自动填充服务声明输入内容。
    var textContentType: UITextContentType {
        switch self {
        case .username: .username
        case .email: .emailAddress
        }
    }

    /// 邮箱使用专用键盘，账号保持普通键盘。
    var keyboardType: UIKeyboardType {
        switch self {
        case .username: .default
        case .email: .emailAddress
        }
    }
}

/// 来源登录表单（公共）：所有来源共用同一套登录界面、校验与失败文案。
///
/// 来源只提供展示信息（名称／Logo／说明／第一项凭证类型）与提交动作，不各写一份登录页。
/// 可以两种方式使用：
/// - 门禁的登录弹窗：`SourceLoginContent { SourceLoginView(…) }`，`showsCancelButton: true`（弹窗由门禁呈现）；
/// - 来源设置弹窗「个人中心」分页未登录时的内容：内嵌使用，不显示取消按钮。
///
/// 弹窗外观（高度／底色／拖拽指示）由本视图自己声明，与其它弹窗一致；
/// 登录成功后由账号 owner 发布登录状态，页面据此**原位**切成资料内容，本视图不负责关闭或跳转。
struct SourceLoginView: View {
    private enum Field: Hashable {
        case identifier
        case password
    }

    private let sourceName: String
    private let logo: SourceLogo
    private let prompt: String
    private let identifierKind: SourceLoginIdentifierKind
    private let showsCancelButton: Bool
    private let submit: (String, String) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var identifier = ""
    @State private var password = ""
    @State private var isSubmitting = false
    @State private var loginTask: Task<Void, Never>?
    @FocusState private var focusedField: Field?

    init(
        sourceName: String,
        logo: SourceLogo,
        prompt: String,
        identifierKind: SourceLoginIdentifierKind = .username,
        showsCancelButton: Bool = false,
        submit: @escaping (String, String) async throws -> Void,
    ) {
        self.sourceName = sourceName
        self.logo = logo
        self.prompt = prompt
        self.identifierKind = identifierKind
        self.showsCancelButton = showsCancelButton
        self.submit = submit
    }

    /// 只有账号和密码都已输入时才允许提交。
    private var isFormValid: Bool {
        !identifier.isEmpty && !password.isEmpty && !isSubmitting
    }

    var body: some View {
        ZStack {
            SourceLoginBackground()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    header
                    form
                        .padding(.horizontal, 24)
                        .padding(.bottom, 32)
                }
                .padding(.top, 24)
            }
        }
        // 弹窗是独立 presentation，外观由本视图声明；内嵌在设置分页里时这些修饰符不生效。
        .presentationDetents([.fraction(3 / 4)])
        .presentationBackground(Color.pageBackground)
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(isSubmitting)
        .onDisappear {
            loginTask?.cancel()
            loginTask = nil
            password = ""
            isSubmitting = false
        }
    }

    /// 用来源 Logo 与名称说明当前登录的是哪个来源。
    private var header: some View {
        VStack(spacing: 18) {
            SourceLogoView(logo, size: 96)
                .background {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(Color.surfaceElevated)
                        .shadow(color: .black.opacity(0.08), radius: 24, x: 0, y: 12)
                }

            VStack(spacing: 6) {
                Text(sourceName)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(Color.textPrimary)

                Text(prompt)
                    .font(.subheadline)
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .padding(.top, 48)
        .padding(.bottom, 24)
    }

    /// 账号、密码与提交操作。
    private var form: some View {
        VStack(spacing: 20) {
            inputField(
                title: identifierKind.title,
                systemImage: "person.fill",
                text: $identifier,
                field: .identifier,
                textContentType: identifierKind.textContentType,
                keyboardType: identifierKind.keyboardType,
            )

            inputField(
                title: "密码",
                systemImage: "lock.fill",
                text: $password,
                field: .password,
                isSecure: true,
            )

            loginButton

            if showsCancelButton {
                Button("暂不登录") {
                    dismiss()
                }
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)
                .disabled(isSubmitting)
            }
        }
        .padding(24)
        .disabled(isSubmitting)
    }

    /// 一个账号或密码输入行（图标 + 输入框 + 清空按钮）。
    private func inputField(
        title: String,
        systemImage: String,
        text: Binding<String>,
        field: Field,
        isSecure: Bool = false,
        textContentType: UITextContentType? = nil,
        keyboardType: UIKeyboardType = .default,
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.brandPrimary)
                .frame(width: 20)

            Group {
                if isSecure {
                    SecureField("请输入\(title)", text: text)
                        .textContentType(.password)
                } else {
                    TextField("请输入\(title)", text: text)
                        .textContentType(textContentType)
                        .keyboardType(keyboardType)
                }
            }
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(Color.textPrimary)
            .lineLimit(1)
            .frame(height: 22)
            .focused($focusedField, equals: field)
            .submitLabel(field == .identifier ? .next : .go)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .onSubmit {
                handleSubmit(for: field)
            }

            if !text.wrappedValue.isEmpty {
                Button {
                    text.wrappedValue = ""
                    focusedField = field
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.textTertiary)
                        .frame(width: 24, height: 24)
                        .contentShape(.circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("清空\(title)")
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 56)
        .background {
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.surfaceElevated)
        }
    }

    /// 随表单完整性变化的登录按钮。
    private var loginButton: some View {
        Button(action: performLogin) {
            Group {
                if isSubmitting {
                    ProgressView()
                        .tint(Color.textOnPrimary)
                } else {
                    Text("登录")
                        .font(.system(size: 17, weight: .semibold))
                }
            }
            .foregroundStyle(Color.textOnPrimary)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background {
                RoundedRectangle(cornerRadius: 16)
                    .fill(isFormValid || isSubmitting ? Color.brandPrimary : Color.brandPrimary.opacity(0.4))
            }
        }
        .buttonStyle(.plain)
        .disabled(!isFormValid)
    }

    /// 账号行切到密码行，密码行直接提交。
    private func handleSubmit(for field: Field) {
        switch field {
        case .identifier:
            focusedField = .password

        case .password:
            performLogin()
        }
    }

    /// 提交当前输入；成功后由登录状态变化切走本页面，这里只负责失败反馈。
    private func performLogin() {
        guard isFormValid else {
            return
        }

        focusedField = nil
        isSubmitting = true
        let submittedIdentifier = identifier
        let submittedPassword = password

        loginTask = Task {
            defer {
                // 完成后立即释放本次明文密码，不延长其生命周期。
                loginTask = nil
            }

            do {
                try await submit(submittedIdentifier, submittedPassword)
                try Task.checkCancellation()
                password = ""
                isSubmitting = false
                ToastCenter.shared.show("登录成功", type: .success)
            } catch is CancellationError {
                password = ""
                isSubmitting = false
            } catch {
                password = ""
                isSubmitting = false
                ToastCenter.shared.show(Self.errorText(for: error), type: .error)
            }
        }
    }

    /// 登录失败文案：只按公共错误语义给出可操作提示，不暴露来源内部细节。
    private static func errorText(for error: any Error) -> String {
        guard let sourceError = error as? ComicSourceError else {
            return "登录失败，请稍后重试"
        }

        return switch sourceError {
        case .authenticationRequired:
            "账号或密码错误，请重新输入"

        case let .serverRejected(code):
            // 禁漫等来源用 401 表示凭证被拒；其余业务码无法区分具体原因。
            code == "401" ? "账号或密码错误，请重新输入" : "登录失败，请稍后重试"

        case .networkUnavailable:
            "网络连接失败，请检查网络后重试"

        case .timedOut:
            "登录请求超时，请稍后重试"

        case .rateLimited:
            "请求过于频繁，请稍后重试"

        case .invalidIdentity, .invalidResponse:
            "登录失败，请稍后重试"
        }
    }
}

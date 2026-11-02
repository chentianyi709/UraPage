import SwiftUI

/// 禁漫「漫画源设置」分页：繁体分类参数、内容语言、图片图源与服务器线路。
///
/// 全部设置项合并在同一个列表分区、无分组标题；图源与线路都会改动同一个 Client 的准备状态，
/// 因此各自的加载／提交期间禁用对方；本地偏好不改动 Client 准备状态。
struct JMComicSourceSettingsPage: View {
    @Environment(\.jmComicServices) private var services
    @Environment(\.sourceImageRequestInvalidation) private var imageRequestInvalidation

    @State private var hostModel: SourceHostSettingsModel?
    @State private var imageSourceModel: JMComicImageSourceSettingsModel?
    @State private var languageModel: JMComicContentLanguageSettingsModel?

    var body: some View {
        Form {
            if let languageModel {
                JMComicSourcePreferenceFields(
                    services: services,
                    languageModel: languageModel,
                    isExternallyDisabled: (imageSourceModel?.isBusy ?? false) || (hostModel?.isBusy ?? false),
                )
            }

            if let imageSourceModel {
                JMComicImageSourceSettingsContent(
                    model: imageSourceModel,
                    isExternallyDisabled: (hostModel?.isBusy ?? false) ||
                        (languageModel?.isUpdating ?? false),
                )
            }

            if let hostModel {
                SourceHostSettingsContent(
                    model: hostModel,
                    isExternallyDisabled: (imageSourceModel?.isBusy ?? false) ||
                        (languageModel?.isUpdating ?? false),
                )
            }
        }
        .task {
            guard hostModel == nil, imageSourceModel == nil, languageModel == nil else {
                return
            }

            let services = services
            let imageSourceModel = JMComicImageSourceSettingsModel(
                services: services,
                invalidateImageRequests: {
                    imageRequestInvalidation.invalidateBrowsingImageRequests(for: services.sourceID)
                },
            )
            let hostModel = SourceHostSettingsModel(
                services: services,
                // 线路切换会改动远程 Setting 里的图片 Host，成功后刷新图源行。
                onHostSelected: { await imageSourceModel.reload() },
            )
            let languageModel = JMComicContentLanguageSettingsModel(
                services: services,
                // 语言切换会重新请求 Setting；图片 Host 可能变化，按图源切换同样失效在途图片请求。
                invalidateImageRequests: {
                    imageRequestInvalidation.invalidateBrowsingImageRequests(for: services.sourceID)
                },
                // 同时刷新图源行显示的新图片 Host 与候选。
                onSettingUpdated: { [weak imageSourceModel] in
                    imageSourceModel?.reload()
                },
            )
            self.hostModel = hostModel
            self.imageSourceModel = imageSourceModel
            self.languageModel = languageModel
            hostModel.loadIfNeeded()
            imageSourceModel.loadIfNeeded()
        }
    }
}

/// 禁漫「漫画源设置」里的偏好设置项：繁体分类参数与内容语言。
///
/// 由页面放进同一个列表分区（不再自带分组）。分类参数是纯本地偏好；内容语言由
/// `JMComicContentLanguageSettingsModel` 提交，并用新语言重新获取远程 Setting。
private struct JMComicSourcePreferenceFields: View {
    let services: JMComicServices
    let languageModel: JMComicContentLanguageSettingsModel

    /// 图源或线路正在更新远程 Setting 时禁用语言；三者共用同一个 Client 状态。
    var isExternallyDisabled = false

    @State private var usesTraditionalCategoryParameter: Bool

    init(
        services: JMComicServices,
        languageModel: JMComicContentLanguageSettingsModel,
        isExternallyDisabled: Bool = false,
    ) {
        self.services = services
        self.languageModel = languageModel
        self.isExternallyDisabled = isExternallyDisabled
        _usesTraditionalCategoryParameter = State(
            initialValue: services.selectedUsesTraditionalCategoryParameter(),
        )
    }

    var body: some View {
        classificationRow
        languageRow
            .onChange(of: languageModel.errorMessage) { _, errorMessage in
                guard let errorMessage else { return }

                ToastCenter.shared.show(errorMessage, type: .error)
            }
    }

    /// 内容语言：所有禁漫 GET 请求的 `lang` 参数；切换后重新获取远程 Setting。
    private var languageRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 12) {
                Text("内容语言")

                Spacer(minLength: 16)

                // 只表示本行自己的提交进度；其它设置忙时只禁用选择，避免误导成语言正在切换。
                if languageModel.isUpdating {
                    ProgressView()
                        .controlSize(.small)
                        .tint(Color.brandPrimary)
                        .accessibilityLabel("正在切换内容语言")
                }

                Picker("内容语言", selection: languageSelection) {
                    ForEach(JMComicContentLanguage.allCases, id: \.self) { language in
                        Text(language.displayTitle)
                            .tag(language)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .tint(Color.brandPrimary)
                .disabled(languageModel.isUpdating || isExternallyDisabled)
            }

            Text("切换后重新获取远程设置；已加载的内容不变")
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
        }
    }

    /// 把菜单选择交给模型提交；失败由模型回到已确认值。
    private var languageSelection: Binding<JMComicContentLanguage> {
        Binding(
            get: { languageModel.displayedLanguage },
            set: { languageModel.select($0) },
        )
    }

    /// 分类参数转换：分类接口是否把分类名转为繁体（结果与首页展示更一致）。
    private var classificationRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle("繁体分类参数", isOn: $usesTraditionalCategoryParameter)
                .onChange(of: usesTraditionalCategoryParameter) { _, newValue in
                    services.selectUsesTraditionalCategoryParameter(newValue)
                }

            Text("使分类结果与首页内容更一致")
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
        }
    }
}

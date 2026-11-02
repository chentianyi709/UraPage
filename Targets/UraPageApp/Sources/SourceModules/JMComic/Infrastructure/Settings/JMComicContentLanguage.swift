/// 禁漫 API 支持的内容语言选项，对应所有 GET 请求的 `lang` 参数。
enum JMComicContentLanguage: String, CaseIterable, Sendable {
    /// 简体中文，对应接口值 `CN`。
    case simplifiedChinese = "CN"

    /// 繁体中文，对应接口值 `TW`。
    case traditionalChinese = "TW"

    /// 返回设置页选择器展示的名称。
    var displayTitle: String {
        switch self {
        case .simplifiedChinese:
            "简体中文"
        case .traditionalChinese:
            "繁体中文"
        }
    }
}

/// 哔咔 API 通过 `image-quality` 请求头支持的图片质量选项。
enum BikaImageQuality: String, CaseIterable, Hashable, Sendable {
    /// 请求低质量图片。
    case low

    /// 请求中等质量图片。
    case medium

    /// 请求高质量图片。
    case high

    /// 请求服务端提供的原始质量图片。
    case original

    /// 来源设置页面展示的简短名称。
    var displayTitle: String {
        switch self {
        case .low:
            "低"
        case .medium:
            "中"
        case .high:
            "高"
        case .original:
            "原画"
        }
    }
}

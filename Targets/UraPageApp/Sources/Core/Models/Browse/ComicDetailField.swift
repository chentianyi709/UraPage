import Foundation

/// 详情页统一字段行的一项：图标 + 紧凑文案。
///
/// 展示哪些字段、什么顺序完全由来源决定（浏览量、点赞、图片数、评分、语言……），
/// 公共层只负责版式与无障碍，不解析数值、不预设字段集合。
/// `value` 是已经格式化好的文案（例如 "12.3万" / "2024-05" / "已完结"），
/// 需要统一格式的常见字段用下面的便利构造，格式变化时只改一处。
struct ComicDetailField: Hashable, Codable, Sendable {
    /// 展示文案。
    let value: String

    /// 字段图标。
    let systemImage: String

    /// 读屏文案；`nil` 时退回 `value`。
    let accessibilityText: String?

    init(value: String, systemImage: String, accessibilityText: String? = nil) {
        self.value = value
        self.systemImage = systemImage
        self.accessibilityText = accessibilityText
    }
}

extension ComicDetailField {
    /// 浏览量，紧凑数字（例如 "12.3万"）。
    static func viewCount(_ count: Int) -> Self {
        let text = count.formatted(.number.notation(.compactName))
        return Self(value: text, systemImage: "flame", accessibilityText: "浏览量 \(text)")
    }

    /// 点赞数，紧凑数字。
    static func likeCount(_ count: Int) -> Self {
        let text = count.formatted(.number.notation(.compactName))
        return Self(value: text, systemImage: "heart", accessibilityText: "点赞数 \(text)")
    }

    /// 图片数量。
    static func pageCount(_ count: Int) -> Self {
        Self(value: "\(count)P", systemImage: "photo", accessibilityText: "图片数量 \(count)")
    }

    /// 发布日期；空白视为来源未提供。
    static func publishedDate(_ text: String) -> Self? {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            return nil
        }

        return Self(value: trimmedText, systemImage: "calendar", accessibilityText: "发布日期 \(trimmedText)")
    }

    /// 连载状态。
    static func serialization(isFinished: Bool) -> Self {
        isFinished
            ? Self(value: "已完结", systemImage: "checkmark.circle", accessibilityText: "连载状态 已完结")
            : Self(value: "连载中", systemImage: "clock", accessibilityText: "连载状态 连载中")
    }
}

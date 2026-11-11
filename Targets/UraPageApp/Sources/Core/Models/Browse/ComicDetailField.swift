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

    /// 点击字段弹出的说明；`nil` 表示该字段不可点、不弹说明。
    ///
    /// 字段行只有图标和数字，这行说明就是用户唯一能知道「这个数字是什么」的地方。
    /// 这里保留完整原文（离线快照与读屏都要用），气泡展示时再按屏幕可用宽度单行截断；
    /// 空串或纯空白视为未提供，避免弹出一颗空气泡。
    /// 便利构造给了通用文案，来源要换叫法时用 `withTip(_:)` 覆盖。
    let tip: String?

    init(
        value: String,
        systemImage: String,
        accessibilityText: String? = nil,
        tip: String? = nil,
    ) {
        self.value = value
        self.systemImage = systemImage
        self.accessibilityText = accessibilityText
        self.tip = Self.normalizedTip(tip)
    }
}

extension ComicDetailField {
    /// 去掉两端空白；空白文案按未提供处理。
    private static func normalizedTip(_ tip: String?) -> String? {
        guard let trimmedTip = tip?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmedTip.isEmpty else { return nil }

        return trimmedTip
    }

    /// 浏览量，紧凑数字（例如 "12.3万"）。
    static func viewCount(_ count: Int) -> Self {
        let text = count.formatted(.number.notation(.compactName))
        return Self(
            value: text,
            systemImage: "flame",
            accessibilityText: "浏览量 \(text)",
            tip: "浏览量",
        )
    }

    /// 点赞数，紧凑数字。
    static func likeCount(_ count: Int) -> Self {
        let text = count.formatted(.number.notation(.compactName))
        return Self(
            value: text,
            systemImage: "heart",
            accessibilityText: "点赞数 \(text)",
            tip: "点赞数",
        )
    }

    /// 图片数量。
    static func pageCount(_ count: Int) -> Self {
        Self(
            value: "\(count)P",
            systemImage: "photo",
            accessibilityText: "图片数量 \(count)",
            tip: "图片数量",
        )
    }

    /// 发布日期；空白视为来源未提供。
    static func publishedDate(_ text: String) -> Self? {
        date(text, accessibilityLabel: "发布日期", tip: "发布日期")
    }

    /// 更新日期（作品最后更新时间）；空白视为来源未提供。
    static func updatedDate(_ text: String) -> Self? {
        date(text, accessibilityLabel: "更新时间", tip: "更新时间")
    }

    /// 连载状态。
    static func serialization(isFinished: Bool) -> Self {
        isFinished
            ? Self(
                value: "已完结",
                systemImage: "checkmark.circle",
                accessibilityText: "连载状态 已完结",
                tip: "连载状态",
            )
            : Self(
                value: "连载中",
                systemImage: "clock",
                accessibilityText: "连载状态 连载中",
                tip: "连载状态",
            )
    }

    /// 覆盖字段说明（`nil` 表示不弹）；来源的叫法与通用文案不同时用。
    ///
    /// 用链式覆盖而不是给便利构造加参数：带默认参数的函数不能再当函数值用，
    /// 会让 `map(ComicDetailField.pageCount)` 这类写法失效。
    func withTip(_ tip: String?) -> Self {
        Self(
            value: value,
            systemImage: systemImage,
            accessibilityText: accessibilityText,
            tip: tip,
        )
    }

    /// 日期类字段的统一格式：去掉两端空白，空值不产出字段；读屏用「标签＋日期」。
    private static func date(
        _ text: String,
        accessibilityLabel: String,
        tip: String?,
    ) -> Self? {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            return nil
        }

        return Self(
            value: trimmedText,
            systemImage: "calendar",
            accessibilityText: "\(accessibilityLabel) \(trimmedText)",
            tip: tip,
        )
    }
}

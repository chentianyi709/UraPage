import SwiftUI

/// 业务页面未实现期间的临时占位。
///
/// 只用于各来源 Tab 的试点接入；真实页面就位后逐个替换并删除本组件。
struct PlaceholderPageView: View {
    private let title: String
    private let systemImage: String
    private let detail: String?

    /// - Parameter detail: 额外说明；省略时显示"页面尚未实现"。
    init(title: String, detail: String? = nil, systemImage: String) {
        self.title = title
        self.systemImage = systemImage
        self.detail = detail
    }

    var body: some View {
        ContentUnavailableView(
            title,
            systemImage: systemImage,
            description: Text(detail ?? "页面尚未实现"),
        )
    }
}

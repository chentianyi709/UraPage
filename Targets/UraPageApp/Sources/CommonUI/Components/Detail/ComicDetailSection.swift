import SwiftUI

/// 详情页分区：主色图标＋粗体标题＋内容。
///
/// 简介、分类、标签、相关推荐都用同一套分区外观（与旧项目 `ComicDetailSection` 一致）。
struct ComicDetailSection<Content: View>: View {
    /// 分区标题。
    let title: String

    /// 分区标题前的 SF Symbol。
    let systemImage: String

    @ContentBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.brandPrimary)

                Text(title)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
            }

            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

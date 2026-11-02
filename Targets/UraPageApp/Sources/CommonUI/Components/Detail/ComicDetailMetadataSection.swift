import Foundation
import SwiftUI

/// 详情页作者行与统一字段行。
///
/// 作者按来源顺序内联排列（品牌色、可逐个点击，用「·」分隔）；字段行按固定顺序换行展示
/// 来源真实拥有的字段，并在来源提供复制内容时显示作品 ID。与旧项目 `ComicDetailMetadataSection` 同布局。
struct ComicDetailMetadataSection: View {
    /// 按来源顺序给出的作者名。
    let authorNames: [String]

    /// 统一字段行数据。
    let metadata: ComicDetailMetadata

    /// 作品 ID；空串时不显示 ID 按钮。
    let comicID: String

    /// 点击作品 ID 时生成要复制的内容；`nil` 表示该来源不提供复制。
    let copyContentProvider: ComicDetailCopyProvider?

    /// 作者名点击（下标＋名称）。
    let onSelectAuthorName: (Int, String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !visibleAuthors.isEmpty {
                authorRow
            }

            metadataRow
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 内联作者行：人像图标＋可逐个点击的作者名；整行使用脚注字号，图标与作者名同尺寸。
    private var authorRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "person.fill")
                .foregroundStyle(Color.textSecondary)
                .accessibilityHidden(true)

            Text(authorText)
                .environment(\.openURL, OpenURLAction { url in
                    guard url.scheme == "urapage-author",
                          let index = Int(url.host ?? ""),
                          let author = visibleAuthors.first(where: { $0.index == index })
                    else {
                        return .discarded
                    }

                    onSelectAuthorName(author.index, author.name)
                    return .handled
                })
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.footnote)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 10)
    }

    /// 字段行：图标＋紧凑文字，等宽字体，按固定顺序换行。
    private var metadataRow: some View {
        WrappingFlowLayout(horizontalSpacing: 12, verticalSpacing: 8) {
            if let viewCount = metadata.viewCount {
                let value = viewCount.formatted(.number.notation(.compactName))
                metadataItem(value: value, systemImage: "flame", accessibilityText: "浏览量 \(value)")
            }

            if let likeCount = metadata.likeCount {
                let value = likeCount.formatted(.number.notation(.compactName))
                metadataItem(value: value, systemImage: "heart", accessibilityText: "点赞数 \(value)")
            }

            if let pageCount = metadata.pageCount {
                metadataItem(
                    value: "\(pageCount)P",
                    systemImage: "photo",
                    accessibilityText: "图片数量 \(pageCount)",
                )
            }

            if let publishedDateText = nonempty(metadata.publishedDateText) {
                metadataItem(
                    value: publishedDateText,
                    systemImage: "calendar",
                    accessibilityText: "发布日期 \(publishedDateText)",
                )
            }

            if let chapterCount = metadata.chapterCount {
                metadataItem(
                    value: "\(chapterCount)章",
                    systemImage: "books.vertical",
                    accessibilityText: "章节数量 \(chapterCount)",
                )
            }

            if let serializationStatus = metadata.serializationStatus {
                let value = serializationStatus.displayTitle
                metadataItem(
                    value: value,
                    systemImage: serializationStatus.systemImage,
                    accessibilityText: "连载状态 \(value)",
                )
            }

            if !comicID.isEmpty, let copyContentProvider {
                ComicDetailIdentityButton(comicID: comicID, copyContentProvider: copyContentProvider)
            }
        }
        .font(.caption)
        .foregroundStyle(Color.textSecondary)
        .monospaced()
        .padding(.top, 10)
    }

    /// 一个图标与紧凑文字组成的统一字段项。
    private func metadataItem(
        value: String,
        systemImage: String,
        accessibilityText: String,
    ) -> some View {
        HStack(spacing: 3) {
            Image(systemName: systemImage)
                .accessibilityHidden(true)

            Text(value)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    /// 过滤空白作者，同时保留来源数组的原始下标供点击路由使用。
    private var visibleAuthors: [(index: Int, name: String)] {
        authorNames.enumerated().compactMap { index, authorName in
            let trimmedName = authorName.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmedName.isEmpty ? nil : (index, trimmedName)
        }
    }

    /// 拼成同一段可逐字换行的富文本；链接只在本视图内映射回来源作者下标。
    private var authorText: AttributedString {
        var result = AttributedString()
        for (position, author) in visibleAuthors.enumerated() {
            if position > 0 {
                var separator = AttributedString("\u{202F}· ")
                separator.foregroundColor = Color.textSecondary
                result += separator
            }

            var name = AttributedString(author.name.allowingLineBreakBetweenCharacters)
            name.foregroundColor = Color.brandPrimary
            name.link = URL(string: "urapage-author://\(author.index)")
            result += name
        }
        return result
    }

    /// 把空白文本视为来源未提供。
    private func nonempty(_ value: String?) -> String? {
        guard let value else {
            return nil
        }

        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedValue.isEmpty ? nil : trimmedValue
    }
}

private extension ComicSerializationStatus {
    /// 返回统一字段行使用的状态文字。
    var displayTitle: String {
        switch self {
        case .serializing:
            "连载中"
        case .completed:
            "已完结"
        }
    }

    /// 返回统一字段行使用的状态图标。
    var systemImage: String {
        switch self {
        case .serializing:
            "clock"
        case .completed:
            "checkmark.circle"
        }
    }
}

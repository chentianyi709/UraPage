import Foundation
import SwiftUI

/// 详情页作者行与统一字段行。
///
/// 作者按来源顺序内联排列（品牌色、可逐个点击，用「·」分隔）；字段行按来源给的顺序换行展示
/// 来源真实拥有的字段，并在来源提供复制内容时显示作品 ID；两者都没有时字段行不占位。
/// 与旧项目 `ComicDetailMetadataSection` 同布局。
struct ComicDetailMetadataSection: View {
    /// 按来源顺序给出的作者名。
    let authorNames: [String]

    /// 字段行内容与顺序，由来源给。
    let fields: [ComicDetailField]

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

            if !fields.isEmpty || showsIdentityButton {
                fieldsRow
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 字段为空但来源提供作品 ID 时，字段行仍要保留 ID 入口。
    private var showsIdentityButton: Bool {
        !comicID.isEmpty && copyContentProvider != nil
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

    /// 字段行：图标＋紧凑文字，等宽字体，按来源给的顺序换行。
    private var fieldsRow: some View {
        WrappingFlowLayout(horizontalSpacing: 12, verticalSpacing: 8) {
            ForEach(fields.indices, id: \.self) { index in
                fieldItem(fields[index])
            }

            if showsIdentityButton, let copyContentProvider {
                ComicDetailIdentityButton(comicID: comicID, copyContentProvider: copyContentProvider)
            }
        }
        .font(.caption)
        .foregroundStyle(Color.textSecondary)
        .monospaced()
        .padding(.top, 10)
    }

    /// 一个图标与紧凑文字组成的字段项。
    private func fieldItem(_ field: ComicDetailField) -> some View {
        HStack(spacing: 3) {
            Image(systemName: field.systemImage)
                .accessibilityHidden(true)

            Text(field.value)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(field.accessibilityText ?? field.value)
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
}

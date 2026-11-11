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

    /// 当前展示了说明的字段下标；同一时刻只有一个气泡，再点同一个字段收起。
    /// 用下标而不是字段值：两个内容相同的字段不会同时弹气泡；字段数组有任何变化时下面统一收起。
    @State private var activeTipIndex: Int?

    /// 详情页使用内联导航栏，气泡顶部要让出返回按钮所在的高度。
    private static let navigationBarHeight: CGFloat = 44

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
        // 字段的说明气泡翻到下方时会盖住「开始阅读」等后续兄弟，把这一块提到上层才能压住它们。
        .zIndex(1)
        // 气泡自己会跟着滚动，但不会自己消失：给一个短生命周期，避免一直挂在那里。
        .task(id: activeTipIndex) {
            guard activeTipIndex != nil else { return }

            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }

            activeTipIndex = nil
        }
        .onChange(of: fields) { _, _ in
            // 详情节点的字段被替换后，旧说明可能已经不对应当前内容，直接收起。
            activeTipIndex = nil
        }
        .onDisappear {
            activeTipIndex = nil
        }
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
                fieldEntry(fields[index], index: index)
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

    /// 字段项：有说明的包成按钮，点一下在字段上方弹说明；没有说明就保持纯展示。
    ///
    /// 气泡是自绘的（`tooltip(_:)`），不用系统 `popover`：后者在这个自定义布局里以整行为锚点、
    /// 内容宽度还会被压成一字一行。点击同一个字段收起，点另一个字段直接换位置。
    @ViewBuilder
    private func fieldEntry(_ field: ComicDetailField, index: Int) -> some View {
        if let tip = field.tip {
            Button {
                // 不包 `withAnimation`：气泡自己控制淡入淡出，外层动画会把位移也插值。
                activeTipIndex = activeTipIndex == index ? nil : index
            } label: {
                // 透明矩形覆盖图标与文字之间的空隙；不改变视觉，也不额外提示可点。
                fieldItem(field)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            // 气泡本身对读屏隐藏，完整 tip 已在字段的无障碍文案里；这里只在两者说法不同时补充，
            // 相同时返回空串，避免 VoiceOver 重复朗读。
            .accessibilityValue(spokenTip(tip, for: field))
            .tooltip(
                activeTipIndex == index ? tip : nil,
                topReservedHeight: Self.navigationBarHeight,
            ) {
                activeTipIndex = nil
            }
        } else {
            fieldItem(field)
        }
    }

    /// 气泡内容对读屏是隐藏的：tip 若带了字段名里没有的说法，用 value 补上，
    /// 否则这条解释只有明眼人看得到。两者一致时返回空串，避免重复朗读。
    private func spokenTip(_ tip: String, for field: ComicDetailField) -> String {
        let spokenText = field.accessibilityText ?? field.value

        return spokenText.contains(tip) ? "" : tip
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

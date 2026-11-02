import SwiftUI

/// 按来源给出的章节顺序展示目录；正反序只影响当前弹窗，列数在所有来源间共享。
struct ComicChaptersSheet<Chapter: Identifiable>: View {
    let chapters: [Chapter]
    let title: KeyPath<Chapter, String>
    /// 由调用页面提供已保存的章节身份；弹窗不读取持久化数据。
    let lastReadChapterID: Chapter.ID?
    let onSelect: (Chapter) -> Void

    init(
        chapters: [Chapter],
        title: KeyPath<Chapter, String>,
        lastReadChapterID: Chapter.ID? = nil,
        onSelect: @escaping (Chapter) -> Void,
    ) {
        self.chapters = chapters
        self.title = title
        self.lastReadChapterID = lastReadChapterID
        self.onSelect = onSelect
    }

    var body: some View {
        ChapterGridSheet(
            title: "章节列表（\(chapters.count)）",
            items: chapters,
        ) { chapter in
            chapterCell(chapter)
        } bottomBar: {
            // 章节列表弹窗没有底部工具栏；槽位不能传空闭包（iOS 26 上 `EmptyView` 不是 `ToolbarContent`），用空分组占位。
            ToolbarItemGroup(placement: .bottomBar) {}
        }
    }

    /// 单个章节：标题 + 可选「上次阅读」角标。
    private func chapterCell(_ chapter: Chapter) -> some View {
        let isLastReadChapter = chapter.id == lastReadChapterID

        return Button {
            onSelect(chapter)
        } label: {
            Text(chapter[keyPath: title])
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.textPrimary)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.surface)
                }
        }
        .buttonStyle(.plain)
        .overlay(alignment: .top) {
            if isLastReadChapter {
                Text("上次阅读")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(Color.textOnPrimary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.brandPrimary, in: Capsule())
                    .offset(y: -8)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityValue(isLastReadChapter ? "上次阅读" : "")
    }
}

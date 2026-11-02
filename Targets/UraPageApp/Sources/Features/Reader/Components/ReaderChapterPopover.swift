import SwiftUI

/// 描述 Reader 章节 popover 中一条已经由来源页面组装好的展示选项。
struct ReaderChapterMenuOption: Identifiable {
    let id: ChapterIdentity
    let title: String
}

/// Reader 章节 popover 内容：可滚动的章节列表、进入时定位当前章、选中后回调。
///
/// 缩放转场与页码胶囊共用外层传入的命名空间；关闭 popover 由回调方负责，
/// 本视图只表达「选中了哪一章」。
struct ReaderChapterPopover: View {
    /// 页码胶囊与 popover 共用的缩放转场 id；两边必须一致，否则转场会静默失效。
    static let zoomTransitionID = "READER_CHAPTER_MENU"

    let chapters: [ReaderChapterMenuOption]
    let selectedChapterID: ChapterIdentity?
    let namespace: Namespace.ID
    let onSelectChapter: (ChapterIdentity) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(chapters) { option in
                        Button {
                            onSelectChapter(option.id)
                        } label: {
                            HStack {
                                if option.id == selectedChapterID {
                                    Image(systemName: "checkmark")
                                        .frame(width: 20)
                                } else {
                                    Color.clear
                                        .frame(width: 20, height: 20)
                                }
                                Text(option.title)
                                    .lineLimit(1)
                                Spacer()
                            }
                            .padding(.horizontal, 20)
                            .frame(height: 48)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .id(option.id)
                    }
                }
                .padding(.vertical, 8)
            }
            .frame(width: 280, height: 430)
            .onAppear {
                if let selectedChapterID {
                    proxy.scrollTo(selectedChapterID, anchor: .center)
                }
            }
        }
        .clipShape(.rect(cornerRadius: 18, style: .continuous))
        .presentationBackground(.clear)
        .presentationCompactAdaptation(.popover)
        .navigationTransition(
            .zoom(
                sourceID: Self.zoomTransitionID,
                in: namespace,
            ),
        )
    }
}

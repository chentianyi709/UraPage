import SwiftUI

/// 汇总左下角页码组件一次渲染所需的来源无关展示数据。
struct ReaderPageIndicatorPresentation {
    let state: ReaderPageIndicatorState
    let chapterTitle: String?
    let selectedChapterID: ChapterIdentity?
}

/// 隔离 Reader 高频页码观察，并把来源组装的数据交给通用页码组件。
///
/// 展示数据通过闭包延迟获取，因此页码变化只会更新这个 Panel，
/// 不会扩大到来源 Reader 的整体内容树。
struct ReaderPageIndicatorPanel: View {
    let presentation: () -> ReaderPageIndicatorPresentation?
    let chapters: [ReaderChapterMenuOption]
    let onSelectChapter: ((ChapterIdentity) -> Void)?

    /// 创建通用页码 Panel；单章节来源无需提供章节菜单配置。
    init(
        presentation: @escaping () -> ReaderPageIndicatorPresentation?,
        chapters: [ReaderChapterMenuOption] = [],
        onSelectChapter: ((ChapterIdentity) -> Void)? = nil,
    ) {
        self.presentation = presentation
        self.chapters = chapters
        self.onSelectChapter = onSelectChapter
    }

    var body: some View {
        if let presentation = presentation() {
            ReaderPageIndicatorView(
                state: presentation.state,
                chapterTitle: presentation.chapterTitle,
                chapters: chapters,
                selectedChapterID: presentation.selectedChapterID,
                onSelectChapter: onSelectChapter,
            )
        }
    }
}

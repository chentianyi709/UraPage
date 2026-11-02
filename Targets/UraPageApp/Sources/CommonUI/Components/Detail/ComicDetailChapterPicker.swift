import SwiftUI

/// 公共章节弹窗：来源页面持有展示状态，使用系统默认 Sheet 转场。
private struct ComicDetailChapterPicker<Chapter: Identifiable>: ViewModifier {
    @Binding var isPresented: Bool

    let chapters: [Chapter]
    let title: KeyPath<Chapter, String>
    let lastReadChapterID: Chapter.ID?
    let onSelect: (Chapter) -> Void

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $isPresented) {
                ComicChaptersSheet(
                    chapters: chapters,
                    title: title,
                    lastReadChapterID: lastReadChapterID,
                ) { chapter in
                    // 关闭和跳转在同一次点击中执行，不等待弹窗动画或异步延迟。
                    isPresented = false
                    onSelect(chapter)
                }
                .presentationDetents([.fraction(2.0 / 3.0), .large])
                .presentationBackground(Color.pageBackground)
                .presentationDragIndicator(.visible)
            }
    }
}

extension View {
    /// 安装章节弹窗；底栏按钮及显示条件由来源页面提供，阅读路由仍由来源处理。
    func comicDetailChapterPicker<Chapter: Identifiable>(
        isPresented: Binding<Bool>,
        chapters: [Chapter],
        title: KeyPath<Chapter, String>,
        lastReadChapterID: Chapter.ID? = nil,
        onSelect: @escaping (Chapter) -> Void,
    ) -> some View {
        modifier(
            ComicDetailChapterPicker(
                isPresented: isPresented,
                chapters: chapters,
                title: title,
                lastReadChapterID: lastReadChapterID,
                onSelect: onSelect,
            ),
        )
    }
}

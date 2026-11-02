import SwiftUI

/// 安装绅士章节打开能力；唯一章节作为公共 Reader 的单元素输入。
struct ShenshiReaderView: View {
    @Environment(\.shenshiServices) private var services

    let input: ComicReaderInput

    var body: some View {
        SourceComicReaderView(input: input) { identity in
            try await services.chapterContentService().openChapter(identity)
        }
    }
}

import SwiftUI

/// 安装禁漫章节打开能力，单章与多章都使用公共 Reader。
struct JMComicReaderView: View {
    @Environment(\.jmComicServices) private var services

    let input: ComicReaderInput

    var body: some View {
        SourceComicReaderView(input: input) { identity in
            try await services.chapterContentService().openChapter(identity)
        }
    }
}

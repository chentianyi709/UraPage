import Foundation
import SwiftUI

/// 根据 Reader 输入选择章节数据提供者；在线与离线最终进入同一个 `ComicReaderView`。
struct SourceComicReaderView: View {
    @Environment(\.downloadManager) private var downloadManager

    @State private var downloadedSessionNamespace = UUID()

    let input: ComicReaderInput
    let openOnlineChapter: @Sendable (ChapterIdentity) async throws -> any SourceOpenedChapter

    var body: some View {
        let manager = downloadManager
        let loadOnlinePage: ReaderPageAccess.OnlineChapterPageLoader = { page, chapter, consume in
            try await manager.withPagePayload(
                for: page,
                using: chapter,
                consume: consume,
            )
        }

        if input.contentMode == .offline {
            ComicReaderView(
                input: input,
                openChapter: { identity in
                    try await manager.openDownloadedChapter(
                        identity,
                        readerSessionID: downloadedSessionNamespace,
                    )
                },
                loadOnlinePage: loadOnlinePage,
                downloadedContent: ReaderDownloadedContent(
                    sessionMemoryNamespace: downloadedSessionNamespace,
                    payload: { page in
                        try await manager.downloadedPagePayload(for: page)
                    },
                    close: {
                        // 会话内容任务已结束（ReaderSession.close 的屏障），此时释放资产 lease。
                        await manager.releaseDownloadedAssetLease(
                            readerSessionID: downloadedSessionNamespace,
                        )
                    },
                ),
            )
        } else {
            ComicReaderView(
                input: input,
                openChapter: openOnlineChapter,
                loadOnlinePage: loadOnlinePage,
            )
        }
    }
}

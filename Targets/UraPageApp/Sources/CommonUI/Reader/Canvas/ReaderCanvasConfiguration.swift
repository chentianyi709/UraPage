import Foundation

/// 只描述 Canvas 创建页面任务时使用的初始执行优先级，不限制并发数量。
enum ReaderPageLoadPriority {
    case visible
    case preload

    /// 当前可见页使用更高的 Swift 任务优先级，预加载页使用 utility。
    var taskPriority: TaskPriority {
        switch self {
        case .visible:
            .userInitiated
        case .preload:
            .utility
        }
    }
}

/// 保存一次 SwiftUI 到 UIKit Canvas 的来源无关内容快照。
struct ReaderCanvasSnapshot {
    let pages: [ReaderPageSlot]
    let scrollRequest: ReaderCanvasScrollRequest?
    let contentVersion: Int
    /// 最近一次完整替换时的 contentVersion；其后的快照变化只向窗口两端扩展。
    /// 已有槽位的真实身份、图片和错误由 Canvas 页面任务原地更新，不替换节点。
    /// SwiftUI 即使合并了替换与扩展，Canvas 也能识别必须重置的内容。
    let replacementVersion: Int
    let topBoundaryPresentation: ReaderCanvasChapterBoundaryPresentation?
    let bottomBoundaryPresentation: ReaderCanvasChapterBoundaryPresentation?
}

/// 互斥描述在线页面与受管理离线资产的取得能力。
///
/// 旧任务继续使用创建时的枚举快照；离线 case 没有网络 closure 或任意文件 URL。
nonisolated enum ReaderPageAccess: Sendable {
    typealias PageResolver = @Sendable (ReaderPagePosition) async throws -> [ComicPage]
    /// 载荷消费者在并发执行器运行，不占用共享页传输 actor（解码／编码属于重活）。
    typealias OnlinePayloadConsumer = @concurrent @Sendable (SourcePagePayload) async throws -> Void
    typealias OnlinePageLoader = @Sendable (ComicPage, OnlinePayloadConsumer) async throws -> Void
    typealias OnlineChapterPageLoader = @Sendable (
        ComicPage,
        any SourceOpenedChapter,
        OnlinePayloadConsumer,
    ) async throws -> Void
    typealias DownloadedPayload = @Sendable (ComicPage) async throws -> SourcePagePayload

    case online(
        resolve: PageResolver,
        loadPage: OnlinePageLoader,
    )
    case downloadedAsset(
        sessionMemoryNamespace: UUID,
        payload: DownloadedPayload,
    )

    /// 离线图片只能命中当前 ReaderSession 的内存命名空间。
    var sessionMemoryNamespace: UUID? {
        guard case let .downloadedAsset(namespace, _) = self else {
            return nil
        }

        return namespace
    }

    /// 只有在线路径能重新下载页面；离线只读本地资产，失败无法靠重试恢复。
    var canRetryPageLoad: Bool {
        if case .online = self {
            return true
        }

        return false
    }
}

/// 集中 Canvas 发给来源 Reader 和控制器的低频事件。
struct ReaderCanvasEvents {
    let onReachTop: (() -> Void)?
    let onReachBottom: (() -> Void)?
    let onRetryTopBoundary: (() -> Void)?
    let onRetryBottomBoundary: (() -> Void)?
    let onCurrentPageChange: (ReaderPageSlot) -> Void
    let onStablePageChange: (ComicPage) -> Void
    let onScrollRequestHandled: (Int) -> Void
    let onTap: () -> Void
    let onScrollStart: () -> Void
}

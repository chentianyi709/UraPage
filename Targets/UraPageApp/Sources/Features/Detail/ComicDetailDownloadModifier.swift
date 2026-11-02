import SwiftUI

/// 详情页下载接线的公共安装点：在线时创建并订阅下载控制器，挂载选章弹窗。
///
/// 三来源详情共用，替代各自重复的「控制器状态 + 选章弹窗 + 下载点击」接线。
/// 离线详情不创建控制器，下载状态与弹窗都保持空闲。
struct ComicDetailDownloadModifier: ViewModifier {
    @Environment(\.downloadManager) private var manager

    /// 详情页持有的下载控制器；由本 modifier 在在线模式下创建并回写。
    @Binding var controller: ComicDownloadController?

    let identity: ComicIdentity
    let contentMode: ComicContentMode

    /// 可加入下载队列的章节；详情未加载时为空。
    let chapters: [DownloadChapterCandidate]

    /// 作品展示快照；详情未加载时为 `nil`，此时不接收入队。
    let snapshot: DownloadedComicDetailSnapshot?

    func body(content: Content) -> some View {
        content
            .downloadChapterSelectionSheet(
                isPresented: isSheetPresented,
                items: items,
            ) { selected in
                guard let snapshot else { return }

                controller?.enqueue(
                    selected,
                    chapters: chapters,
                    snapshot: snapshot,
                )
            }
            .task {
                guard contentMode == .online else { return }

                controller = await ComicDownloadController.makeOrRefresh(
                    existing: controller,
                    manager: manager,
                    identity: identity,
                )
            }
    }

    /// 控制器为 `nil`（离线或尚未创建）时弹窗保持关闭。
    private var isSheetPresented: Binding<Bool> {
        Binding(
            get: { controller?.isSheetPresented ?? false },
            set: { controller?.isSheetPresented = $0 },
        )
    }

    private var items: [DownloadChapterSelectionItem] {
        controller?.selectionItems(for: chapters) ?? []
    }
}

extension View {
    /// 安装详情页下载接线：在线时在详情出现后创建控制器并订阅下载状态。
    ///
    /// 与 `ComicDetailBottomToolbar` 读取同一个 `ComicDownloadController`；
    /// 来源只提供当前展示的章节与快照，不自己维护弹窗与控制器生命周期。
    func comicDetailDownload(
        controller: Binding<ComicDownloadController?>,
        identity: ComicIdentity,
        contentMode: ComicContentMode,
        chapters: [DownloadChapterCandidate],
        snapshot: DownloadedComicDetailSnapshot?,
    ) -> some View {
        modifier(ComicDetailDownloadModifier(
            controller: controller,
            identity: identity,
            contentMode: contentMode,
            chapters: chapters,
            snapshot: snapshot,
        ))
    }
}

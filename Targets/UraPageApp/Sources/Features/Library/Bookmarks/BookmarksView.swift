import SwiftUI
import UIKit

/// 书架「书签」页：本地关注的作者与收藏的分类／标签，按类型分段展示，点胶囊直接进入对应列表。
///
/// 「关注」固定在第一段，跨来源混排；其后按维度分段（分类 → 标签 → 未登记维度）。
/// 每枚胶囊左侧是来源 Logo——同名条目在不同来源是两条，靠它区分点进去会到哪个来源。
/// 页面整体走 `LazyVStack`：仓库里只构建可见的段与胶囊，书签再多也不会一次全部渲染。
/// 长按胶囊可复制名称或删除该条（关注与标签都是「删除」）；每段标题右侧的垃圾桶清空该段，需二次确认。
struct BookmarksView: View {
    @Environment(\.appShell) private var shell
    @Environment(\.bookmarkStore) private var bookmarkStore

    @Environment(\.followingStore) private var followingStore

    @State private var model: BookmarksViewModel?

    /// 待确认清空的段；非空时弹出二次确认。
    @State private var pendingClear: ClearTarget?

    let isActive: Bool

    var body: some View {
        InitialLoadView(
            model: model,
            initialState: { $0.loadState },
            isEmpty: { $0.isEmpty },
        ) {
            BookmarksSkeleton()
        } empty: {
            EmptyStateView(
                title: "还没有关注或标签",
                message: "在作者、分类、标签页面点右上角的心形图标，就会出现在这里",
            )
            .frame(maxHeight: .infinity)
        } failure: { model, error in
            LoadErrorView(title: "书签加载失败", message: error.message, onRetry: model.refresh)
                .frame(maxHeight: .infinity)
        } content: { model in
            content(model)
        }
        .task(id: isActive) {
            guard isActive else {
                model?.setActive(false)
                return
            }

            if model == nil {
                model = BookmarksViewModel(bookmarkStore: bookmarkStore, followingStore: followingStore)
                // 首次进入读一次；之后新增／删除由保存通知驱动刷新，
                // 切回或从二级页返回只在「不可见期间有过写入」时补读一次。
                model?.startObservingChanges()
                model?.setActive(true)
                model?.refresh()
            } else if let current = model, case .failed = current.loadState {
                // 上次失败，切回时再试一次，不必让用户手动点重试。
                current.setActive(true)
                current.refresh()
            } else {
                // 可见期间的写入仍由保存通知驱动；不可见期间的只记了脏，这里补一次。
                model?.setActive(true)
            }
        }
    }

    private func content(_ model: BookmarksViewModel) -> some View {
        let descriptors = shell.sourceDescriptors
        let logos = Dictionary(uniqueKeysWithValues: descriptors.map { ($0.sourceID, $0.logo) })
        let names = Dictionary(uniqueKeysWithValues: descriptors.map { ($0.sourceID, $0.displayName) })
        let ranks = Dictionary(uniqueKeysWithValues: descriptors.enumerated().map {
            ($0.element.sourceID, $0.offset)
        })

        let followings = ordered(model.followings, by: \.sourceID, ranks: ranks)
        let groups = model.groups.map { group in
            BookmarkGroup(kindID: group.kindID, entries: ordered(group.entries, by: \.sourceID, ranks: ranks))
        }

        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                if !followings.isEmpty {
                    CapsuleSection(
                        title: "关注",
                        clearAccessibilityLabel: "清空关注",
                        onClear: { pendingClear = .followings },
                    ) {
                        MarkCapsuleList(
                            entries: followings,
                            logos: logos,
                            sourceNames: names,
                            sourceID: \.sourceID,
                            text: \.name,
                            kindTitle: { _ in ComicTagKind.author.title },
                            onSelect: { open($0.bookmark) },
                            onRemove: model.unfollow,
                        )
                    }
                }

                ForEach(groups) { group in
                    let kind = KindPresentation(kindID: group.kindID)
                    CapsuleSection(
                        title: kind.title,
                        clearAccessibilityLabel: "清除全部\(kind.title)",
                        onClear: { pendingClear = .kind(group.kindID, title: kind.title) },
                    ) {
                        MarkCapsuleList(
                            entries: group.entries,
                            logos: logos,
                            sourceNames: names,
                            sourceID: \.sourceID,
                            text: \.displayName,
                            kindTitle: { _ in kind.title },
                            onSelect: open,
                            onRemove: model.remove,
                        )
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
        .scrollIndicators(.hidden)
        .alert(item: $pendingClear) { target in
            Alert(
                title: Text(target.confirmationTitle),
                message: Text(target.confirmationMessage),
                primaryButton: .destructive(Text(target.confirmTitle)) {
                    switch target {
                    case .followings:
                        model.clearFollowings()
                    case let .kind(kindID, _):
                        model.clear(kindID: kindID)
                    }
                },
                secondaryButton: .cancel(Text("取消")),
            )
        }
    }

    /// 点击条目：交给目标来源还原路由并 push 到当前栈。
    private func open(_ bookmark: Bookmark) {
        do {
            try shell.navigator.open(.bookmark(bookmark))
        } catch {
            AppLogger.warning(
                "书签跳转失败，source=\(bookmark.sourceID.rawValue) kind=\(bookmark.kindID)",
                category: "Bookmarks",
            )
            ToastCenter.shared.show("这条收藏已失效，请重新收藏", type: .error)
        }
    }

    /// 按来源 Tab 顺序稳定排序：同来源聚在一起，来源内保持传入顺序（最近在前）。
    private func ordered<Value>(
        _ values: [Value],
        by sourceID: KeyPath<Value, ComicSourceID>,
        ranks: [ComicSourceID: Int],
    ) -> [Value] {
        values.enumerated()
            .sorted { lhs, rhs in
                let left = ranks[lhs.element[keyPath: sourceID]] ?? Int.max
                let right = ranks[rhs.element[keyPath: sourceID]] ?? Int.max
                return left == right ? lhs.offset < rhs.offset : left < right
            }
            .map(\.element)
    }
}

/// 段标题：已知维度用协议标题，未登记维度退回标识。
private struct KindPresentation {
    let kindID: String

    var title: String {
        switch kindID {
        case ComicTagKind.author.id: ComicTagKind.author.title
        case ComicTagKind.category.id: ComicTagKind.category.title
        case ComicTagKind.tag.id: ComicTagKind.tag.title
        default: kindID
        }
    }
}

/// 待清空的段。
private enum ClearTarget: Identifiable {
    case followings
    case kind(String, title: String)

    var id: String {
        switch self {
        case .followings: "followings"
        case let .kind(kindID, _): kindID
        }
    }

    var confirmationTitle: String {
        switch self {
        case .followings: "清空关注？"
        case let .kind(_, title): "清除「\(title)」？"
        }
    }

    var confirmationMessage: String {
        switch self {
        case .followings: "将删除全部关注，此操作不可恢复。"
        case let .kind(_, title): "将删除全部「\(title)」收藏，此操作不可恢复。"
        }
    }

    var confirmTitle: String {
        switch self {
        case .followings: "清空"
        case .kind: "清除"
        }
    }
}

/// 一段内的胶囊列表：来源 Logo + 名称，点击进入、长按复制或删除。
private struct MarkCapsuleList<Entry: Hashable>: View {
    let entries: [Entry]
    let logos: [ComicSourceID: SourceLogo]
    let sourceNames: [ComicSourceID: String]
    let sourceID: (Entry) -> ComicSourceID
    let text: (Entry) -> String
    let kindTitle: (Entry) -> String
    let onSelect: (Entry) -> Void
    let onRemove: (Entry) -> Void

    /// 来源 Logo 边长：随字号缩放，不撑高胶囊（文字行高更高）。
    @ScaledMetric(relativeTo: .caption) private var logoSize: CGFloat = 16

    var body: some View {
        WrappingFlowLayout(
            horizontalSpacing: 8,
            verticalSpacing: 8,
        ) {
            ForEach(entries, id: \.self) { entry in
                let sourceID = sourceID(entry)

                Button {
                    onSelect(entry)
                } label: {
                    HStack(spacing: 6) {
                        if let logo = logos[sourceID] {
                            SourceLogoView(logo, size: logoSize, outline: .circle)
                        }

                        Text(text(entry))
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Color.textPrimary)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Color.fillNeutral, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    "\(kindTitle(entry))：\(text(entry))，来源：\(sourceNames[sourceID] ?? sourceID.rawValue)",
                )
                .contextMenu {
                    Button("复制", systemImage: "doc.on.doc") {
                        // 与搜索历史一致：写系统剪贴板后由 Toast 回执。
                        UIPasteboard.general.string = text(entry)
                        ToastCenter.shared.show("已复制", type: .success)
                    }
                    // 菜单项默认跟随全局 tint（品牌红）；复制是中性的查看动作，用主文本色。
                    .tint(Color.textPrimary)

                    Button("删除", systemImage: "trash", role: .destructive) {
                        onRemove(entry)
                    }
                }
                // 与搜索历史一致：删除只留位置动画，被删胶囊立刻离场。
                // 默认淡出会停在原地与补位过来的胶囊重叠，看起来像名字短暂错乱。
                .transition(.asymmetric(insertion: .opacity, removal: .identity))
            }
        }
    }
}

/// 首屏骨架：与真实版式一致的三段标题与胶囊占位（每段走公共 `CapsuleSectionSkeleton`）。
///
/// 标题块按两字标题收窄占位宽度；三段各自六条占位词，贴近「关注 + 若干标签」的真实高度。
private struct BookmarksSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            ForEach(0 ..< 3, id: \.self) { _ in
                CapsuleSectionSkeleton(
                    titleWidth: 48,
                    placeholderTitles: ["作者名称", "分类名称", "标签名称", "短", "中等名称", "偏长一点的名称"],
                )
            }

            Spacer(minLength: 0)
        }
        .padding(16)
    }
}

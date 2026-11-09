import SwiftUI
import UIKit

/// 书架「书签」页：本地收藏的作者／分类／标签，按来源分段展示，点胶囊直接进入对应列表。
///
/// 数据来自跨来源的书签收藏：分组标题是来源名，胶囊左侧用维度图标区分这一条是作者、分类还是标签；
/// 点击时把收藏原样交给目标来源解析路由，因此书架页不需要认识任何来源字段。
/// 长按胶囊可复制名称或删除该条（与搜索历史一致）；每组标题右侧的垃圾桶清空该来源的全部书签，
/// 需二次确认。标题＋胶囊版式与搜索页共用公共 `CapsuleSection`。
struct BookmarksView: View {
    @Environment(\.appShell) private var shell
    @Environment(\.bookmarkStore) private var store

    @State private var model: BookmarksViewModel?

    /// 待确认清空的组；非空时弹出二次确认。
    @State private var pendingClear: BookmarksSection?

    let isActive: Bool

    var body: some View {
        InitialLoadView(
            model: model,
            initialState: { $0.loadState },
            isEmpty: { $0.sections.isEmpty },
        ) {
            BookmarksSkeleton()
        } empty: {
            EmptyStateView(
                title: "还没有书签",
                message: "在作者、分类、标签页面点右上角的书签图标，就能在这里快速回到它们",
            )
            .frame(maxHeight: .infinity)
        } failure: { model, error in
            LoadErrorView(title: "书签加载失败", message: error.message, onRetry: model.refresh)
                .frame(maxHeight: .infinity)
        } content: { model in
            sections(model)
        }
        .task(id: isActive) {
            // 分页容器里四个页面常驻：切到本分区时 `isActive` 变化触发重读，
            // 首次激活同时创建模型；从二级页返回由下面的 `.onAppear` 补一次。
            guard isActive else { return }

            if model == nil {
                model = BookmarksViewModel(store: store)
            }
            model?.refresh()
        }
        .onAppear {
            // 首次出现由 `.task` 创建并加载；这里只处理从二级页返回时的新增收藏。
            // 首次挂载时两边可能同时到达，加载在途就不再排一次全量读取。
            guard isActive, let model, model.loadState != .loading else { return }

            model.refresh()
        }
    }

    private func sections(_ model: BookmarksViewModel) -> some View {
        let descriptors = Dictionary(uniqueKeysWithValues: shell.sourceDescriptors.map {
            ($0.sourceID, $0)
        })
        let pendingName = pendingClear.map {
            descriptors[$0.sourceID]?.displayName ?? $0.sourceID.rawValue
        } ?? ""
        let orderedSections = sectionsInSourceOrder(model.sections)

        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                ForEach(orderedSections) { section in
                    let descriptor = descriptors[section.sourceID]
                    let name = descriptor?.displayName ?? section.sourceID.rawValue

                    CapsuleSection(
                        title: name,
                        clearAccessibilityLabel: "清除全部\(name)书签",
                        onClear: { pendingClear = section },
                    ) {
                        BookmarkCapsuleList(
                            entries: section.entries,
                            sourceName: name,
                            tagKinds: descriptor?.tagKinds ?? [],
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
        .alert(
            "清除全部「\(pendingName)」书签？",
            isPresented: Binding(
                get: { pendingClear != nil },
                set: {
                    if !$0 {
                        pendingClear = nil
                    }
                },
            ),
            presenting: pendingClear,
        ) { section in
            Button("取消", role: .cancel) {}
            Button("清除", role: .destructive) {
                model.clear(sourceID: section.sourceID)
            }
        } message: { section in
            Text("将删除这一组的 \(section.entries.count) 条书签，此操作不可恢复。")
        }
    }

    /// 按来源 Tab 顺序排列分组；未登记的来源排到最后，并保持它们在列表里的相对顺序。
    ///
    /// 排序放在页面而不是视图模型：来源顺序随时可能被拖动调整，模型只在首次加载时分组。
    private func sectionsInSourceOrder(_ sections: [BookmarksSection]) -> [BookmarksSection] {
        let ranks = Dictionary(uniqueKeysWithValues: shell.sourceDescriptors.enumerated().map {
            ($0.element.sourceID, $0.offset)
        })

        return sections.enumerated()
            .sorted { lhs, rhs in
                let left = ranks[lhs.element.sourceID] ?? Int.max
                let right = ranks[rhs.element.sourceID] ?? Int.max
                return left == right ? lhs.offset < rhs.offset : left < right
            }
            .map(\.element)
    }

    /// 点击书签：交给目标来源还原路由并 push 到当前栈。
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
}

/// 书签胶囊：维度图标 + 名称，点击进入、长按删除。
///
/// 来源已经由分组标题表达，胶囊上只标维度——同名的「爱情」既是分类也是标签时，
/// 靠这枚图标区分点进去会到哪种列表。
private struct BookmarkCapsuleList: View {
    let entries: [Bookmark]
    let sourceName: String

    /// 本来源的维度目录；未登记的维度退回标识与通用图标，不隐藏该条。
    let tagKinds: [ComicTagKind]
    let onSelect: (Bookmark) -> Void

    /// 图标位宽度：随文字一起缩放，大字号下不会缩成一小块。
    @ScaledMetric(relativeTo: .caption) private var iconWidth: CGFloat = 14
    let onRemove: (Bookmark) -> Void

    var body: some View {
        WrappingFlowLayout(
            horizontalSpacing: 8,
            verticalSpacing: 8,
        ) {
            ForEach(entries, id: \.identityKey) { bookmark in
                let kind = kind(for: bookmark)

                Button {
                    onSelect(bookmark)
                } label: {
                    HStack(spacing: 6) {
                        // 图标与文字同字号、共用同一个图标位宽度：不同维度的图形宽窄不一，
                        // 统一宽度让所有胶囊的文字左缘对齐，胶囊高度仍由文字行高决定。
                        // 统一取实心变体：维度图标里有描边（person／square.grid.2x2）也有实心（tag.fill），
                        // 小字号下重量差明显，实心版本在同一行里更齐。
                        Image(systemName: kind.systemImage)
                            .symbolVariant(.fill)
                            .font(.caption)
                            .foregroundStyle(Color.textSecondary)
                            .frame(width: iconWidth)

                        Text(bookmark.displayName)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Color.textPrimary)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Color.fillNeutral, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(kind.title)：\(bookmark.displayName)，来源：\(sourceName)")
                .contextMenu {
                    Button("复制", systemImage: "doc.on.doc") {
                        // 与搜索历史一致：写系统剪贴板后由 Toast 回执。
                        UIPasteboard.general.string = bookmark.displayName
                        ToastCenter.shared.show("已复制", type: .success)
                    }
                    // 菜单项默认跟随全局 tint（品牌红）；复制是中性的查看动作，用主文本色。
                    .tint(Color.textPrimary)

                    Button("删除", systemImage: "trash", role: .destructive) {
                        onRemove(bookmark)
                    }
                }
                // 与搜索历史一致：删除只留位置动画，被删胶囊立刻离场。
                // 默认淡出会停在原地与补位过来的胶囊重叠，看起来像名字短暂错乱。
                .transition(.asymmetric(insertion: .opacity, removal: .identity))
            }
        }
    }

    /// 维度展示：来源目录优先，查不到就按未知维度兜底。
    private func kind(for bookmark: Bookmark) -> ComicTagKind {
        tagKinds.first { $0.id == bookmark.kindID } ?? .unknown(bookmark.kindID)
    }
}

/// 首屏骨架：与真实版式一致的三段标题与胶囊占位（每段走公共 `CapsuleSectionSkeleton`）。
///
/// 标题块按四个字的来源名收窄占位宽度；三段各自六条占位词，贴近「每个来源下若干条书签」的真实高度。
private struct BookmarksSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            ForEach(0 ..< 3, id: \.self) { _ in
                CapsuleSectionSkeleton(
                    titleWidth: 72,
                    placeholderTitles: ["作者名称", "分类名称", "标签名称", "短", "中等名称", "偏长一点的名称"],
                )
            }

            Spacer(minLength: 0)
        }
        .padding(16)
    }
}

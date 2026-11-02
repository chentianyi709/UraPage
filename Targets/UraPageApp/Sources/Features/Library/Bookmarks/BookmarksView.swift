import SwiftUI
import UIKit

/// 书架「书签」页：本地收藏的标签／作者／分类，按维度分段展示，点胶囊直接进入对应列表。
///
/// 数据来自跨来源的书签收藏：胶囊展示来源 Logo 与名称，点击时把收藏原样交给
/// 目标来源解析路由，因此书架页不需要认识任何来源字段。长按胶囊可复制名称或删除该条（与搜索历史一致）；
/// 每组标题右侧的垃圾桶清空该组，需二次确认。标题＋胶囊版式与搜索页共用公共 `CapsuleSection`。
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
                message: "在标签、作者、分类页面点右上角的心形，就能在这里快速回到它们",
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
            guard isActive, model != nil else { return }

            model?.refresh()
        }
    }

    private func sections(_ model: BookmarksViewModel) -> some View {
        // 来源展示信息取一次：胶囊上用一个圆形来源 Logo 区分「这条书签来自哪个来源」，
        // 维度已经由分组标题表达，再叠一个维度图标是重复信息。
        let descriptors = Dictionary(uniqueKeysWithValues: shell.sourceDescriptors.map {
            ($0.sourceID, $0)
        })

        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                ForEach(model.sections) { section in
                    CapsuleSection(
                        title: section.kind.title,
                        clearAccessibilityLabel: "清除全部\(section.kind.title)书签",
                        onClear: { pendingClear = section },
                    ) {
                        BookmarkCapsuleList(
                            entries: section.entries,
                            descriptors: descriptors,
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
            "清除全部「\(pendingClear?.kind.title ?? "")」书签？",
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
                model.clear(section.kind)
            }
        } message: { section in
            Text("将删除这一组的 \(section.entries.count) 条书签，此操作不可恢复。")
        }
    }

    /// 点击书签：交给目标来源还原路由并 push 到当前栈。
    private func open(_ bookmark: Bookmark) {
        do {
            try shell.navigator.open(.bookmark(bookmark))
        } catch {
            AppLogger.warning(
                "书签跳转失败，source=\(bookmark.sourceID.rawValue) kind=\(bookmark.kind.rawValue)",
                category: "Bookmarks",
            )
            ToastCenter.shared.show("这条收藏已失效，请重新收藏", type: .error)
        }
    }
}

/// 书签胶囊：来源圆形 Logo + 名称，点击进入、长按删除。
///
/// 维度已经由分组标题表达，胶囊上只标来源——同名的「爱情」在多个来源都收藏过时，
/// 靠这枚 Logo 区分。
private struct BookmarkCapsuleList: View {
    let entries: [Bookmark]
    let descriptors: [ComicSourceID: SourceDescriptor]
    let onSelect: (Bookmark) -> Void
    let onRemove: (Bookmark) -> Void

    var body: some View {
        WrappingFlowLayout(
            horizontalSpacing: 8,
            verticalSpacing: 8,
        ) {
            ForEach(entries, id: \.self) { bookmark in
                Button {
                    onSelect(bookmark)
                } label: {
                    HStack(spacing: 6) {
                        if let logo = descriptors[bookmark.sourceID]?.logo {
                            SourceLogoView(logo, size: 16, outline: .circle)
                        }

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
                .accessibilityLabel(
                    "\(bookmark.kind.title)：\(bookmark.displayName)，来源："
                        + (descriptors[bookmark.sourceID]?.displayName ?? bookmark.sourceID.rawValue),
                )
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
}

/// 首屏骨架：与真实版式一致的分段标题与胶囊占位（每段走公共 `CapsuleSectionSkeleton`，
/// 标题块按两字标题收窄，占位词沿用改版前的三五条，避免用热门搜索的十七个词撑高三行）。
private struct BookmarksSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            ForEach(0 ..< 2, id: \.self) { _ in
                CapsuleSectionSkeleton(
                    titleWidth: 48,
                    placeholderTitles: ["作者名称", "分类名称", "标签名称", "短", "中等名称"],
                )
            }

            Spacer(minLength: 0)
        }
        .padding(16)
    }
}

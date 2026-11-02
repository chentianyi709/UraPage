import SwiftUI

/// 描述 Reader 左下角页码区域当前展示切章占位还是有效页码。
enum ReaderPageIndicatorState: Equatable {
    case switchingChapter
    case loaded(pageNumber: Int, pageTotal: Int)
}

/// 常驻显示 Reader 当前章节页码，并使用通用 popover 提供章节选择。
struct ReaderPageIndicatorView: View {
    private static let maximumChapterTitleCharacterCount = 8

    let state: ReaderPageIndicatorState
    let chapterTitle: String?
    let chapters: [ReaderChapterMenuOption]
    let selectedChapterID: ChapterIdentity?
    let onSelectChapter: ((ChapterIdentity) -> Void)?

    @State private var isChapterPopoverPresented = false
    @Namespace private var namespace

    /// 创建常驻页码提示；只有多章来源需要提供章节菜单配置。
    init(
        state: ReaderPageIndicatorState,
        chapterTitle: String?,
        chapters: [ReaderChapterMenuOption] = [],
        selectedChapterID: ChapterIdentity? = nil,
        onSelectChapter: ((ChapterIdentity) -> Void)? = nil,
    ) {
        self.state = state
        self.chapterTitle = chapterTitle
        self.chapters = chapters
        self.selectedChapterID = selectedChapterID
        self.onSelectChapter = onSelectChapter
    }

    /// 只有存在多个章节时才展示章节选择入口。
    private var canSwitchChapters: Bool {
        chapters.count > 1
            && selectedChapterID != nil
            && onSelectChapter != nil
    }

    /// 把页码提示中的章节标题限制为八个字符，并使用三个等宽句点表示截断。
    private var displayedChapterTitle: String? {
        guard let chapterTitle else {
            return nil
        }
        guard chapterTitle.count > Self.maximumChapterTitleCharacterCount else {
            return chapterTitle
        }

        return String(
            chapterTitle.prefix(Self.maximumChapterTitleCharacterCount),
        ) + "..."
    }

    var body: some View {
        if canSwitchChapters {
            Button {
                isChapterPopoverPresented = true
            } label: {
                indicatorContent
                    .matchedTransitionSource(
                        id: ReaderChapterPopover.zoomTransitionID,
                        in: namespace,
                    )
                    .clipShape(.capsule)
                    .shadow(color: .black.opacity(0.18), radius: 14, y: 7)
            }
            .buttonStyle(.plain)
            // 切章加载期间仍可选择其它章节；只更新目标，不取消旧请求。
            .popover(isPresented: $isChapterPopoverPresented) {
                ReaderChapterPopover(
                    chapters: chapters,
                    selectedChapterID: selectedChapterID,
                    namespace: namespace,
                ) { chapterID in
                    isChapterPopoverPresented = false
                    onSelectChapter?(chapterID)
                }
            }
            .accessibilityLabel("\(pageAccessibilityLabel)，选择章节")
            .accessibilityHint("双击打开章节列表")
        } else {
            indicatorContent
                .clipShape(.capsule)
                .shadow(color: .black.opacity(0.18), radius: 14, y: 7)
                .allowsHitTesting(false)
        }
    }

    /// 绘制胶囊页码内容和多章节提示图标。
    private var indicatorContent: some View {
        HStack(spacing: 0) {
            switch state {
            case .switchingChapter:
                Text("--/--")

            case let .loaded(pageNumber, pageTotal):
                Text(ReaderPageNumberText.pageAndTotal(pageNumber, total: pageTotal))
            }

            if let displayedChapterTitle {
                Text("·")
                    .foregroundStyle(.secondary)

                Text(displayedChapterTitle)
                    .lineLimit(1)
            }

            if canSwitchChapters {
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
            }
        }
        .font(.system(size: 13, weight: .semibold, design: .monospaced))
        .foregroundStyle(.primary)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .fixedSize(horizontal: true, vertical: true)
        .contentShape(.capsule)
        .background(.ultraThinMaterial, in: .capsule)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(pageAccessibilityLabel)
    }

    /// 使用未补零的自然数字描述当前页码，并只为多章节内容附加完整章节标题。
    private var pageAccessibilityLabel: String {
        let chapterDescription = chapterTitle.map { "，章节 \($0)" } ?? ""
        switch state {
        case .switchingChapter:
            return "页码和总页数加载中\(chapterDescription)"

        case let .loaded(pageNumber, pageTotal):
            let validTotal = max(pageTotal, 1)
            let validPageNumber = min(max(pageNumber, 1), validTotal)
            return "第 \(validPageNumber) 页，共 \(validTotal) 页\(chapterDescription)"
        }
    }
}

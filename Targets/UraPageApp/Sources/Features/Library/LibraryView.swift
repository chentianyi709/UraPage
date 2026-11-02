import SwiftUI

/// 书架：所有漫画源共用的收藏／观看历史／下载／书签入口。
///
/// 页面与来源无关：右上角是公共标签切换组件，正文是公共横向分页容器，
/// 两者通过本页三个状态联动（滑动更新指示块、稳定后提交选中页；点标签带动画滑到该页）。
/// 观看历史、下载与书签已接入；漫画收藏仍是占位入口。
struct LibraryView: View {
    @State private var selectedSection: LibrarySection = .favorites
    @State private var pageScrollID: LibrarySection? = .favorites
    @State private var selectionProgress: CGFloat = 0

    var body: some View {
        ZStack {
            Color.pageBackground.ignoresSafeArea()

            HorizontalPagingContainer(
                pages: LibrarySection.allCases,
                selectedPage: $selectedSection,
                pageScrollID: $pageScrollID,
                selectionProgress: $selectionProgress,
            ) { section in
                switch section {
                case .history:
                    ReadingHistoryView(isActive: selectedSection == .history)
                case .downloads:
                    DownloadsView(isActive: selectedSection == .downloads)
                case .bookmark:
                    BookmarksView(isActive: selectedSection == .bookmark)
                case .favorites:
                    PlaceholderPageView(title: section.title, systemImage: section.systemImage)
                }
            }
        }
        .inlineLargeNavigationTitle("书架")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                SlidingTabSwitcher(
                    tabs: LibrarySection.allCases,
                    title: { $0.title },
                    selection: selectedSection,
                    selectionProgress: selectionProgress,
                    onSelect: select,
                )
            }
            // 切换组件自带玻璃背景，隐藏工具栏该位置自带的背景，避免叠成两层。
            .sharedBackgroundVisibility(.hidden)
        }
    }

    /// 点标签：切页并让指示块跟着滑（动画与旧项目一致）。
    private func select(_ section: LibrarySection) {
        withAnimation(.snappy(duration: 0.24)) {
            selectedSection = section
            pageScrollID = section
        }
    }
}

/// 书架内的分区；标题同时用于右上角切换组件与占位页。
///
/// 四个标签共用导航栏右侧的玻璃胶囊切换器，文案保持两字：完整名称会让切换器在
/// 窄屏上压到大标题（四个标签加起来的宽度是固定的）。
private enum LibrarySection: String, CaseIterable, Identifiable {
    case favorites
    case history
    case downloads
    case bookmark

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .favorites:
            "收藏"
        case .history:
            "历史"
        case .downloads:
            "下载"
        case .bookmark:
            "书签"
        }
    }

    var systemImage: String {
        switch self {
        case .favorites:
            "heart"
        case .history:
            "clock.arrow.circlepath"
        case .downloads:
            "arrow.down.circle"
        case .bookmark:
            "bookmark"
        }
    }
}

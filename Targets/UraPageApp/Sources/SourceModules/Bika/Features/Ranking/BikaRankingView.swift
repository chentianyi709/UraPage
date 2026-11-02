import SwiftUI

/// 哔咔排行榜的四个分页：日榜／周榜／月榜（结构相同）与骑士榜（列表行结构）。
///
/// 右上角标签用公共 `SlidingTabSwitcher`、左右分页用公共 `HorizontalPagingContainer`，
/// 两者通过本页三个状态联动；每个分页只在首次选中时加载，切回已加载的分页不重复请求。
enum BikaRankingPage: Hashable, Identifiable {
    case comic(BikaComicRankingPeriod)
    case knights

    var id: Self {
        self
    }

    /// 固定顺序：三个漫画榜周期 + 骑士榜。
    static let all: [BikaRankingPage] = BikaComicRankingPeriod.allCases.map(Self.comic) + [.knights]

    /// 标题栏标签使用的名称。
    var title: String {
        switch self {
        case let .comic(period):
            period.title
        case .knights:
            "骑士榜"
        }
    }
}

/// 哔咔排行榜页面。
struct BikaRankingView: View {
    @Environment(\.appShell) private var shell
    @Environment(\.bikaServices) private var services

    @State private var selectedPage: BikaRankingPage = .comic(.daily)
    @State private var pageScrollID: BikaRankingPage? = .comic(.daily)
    @State private var selectionProgress: CGFloat = 0

    /// 页面级状态 owner；Services 来自本源 Environment，因此首次展示时创建。
    @State private var model: BikaRankingModel?

    var body: some View {
        ZStack {
            Color.pageBackground.ignoresSafeArea()

            if let model {
                HorizontalPagingContainer(
                    pages: BikaRankingPage.all,
                    selectedPage: $selectedPage,
                    pageScrollID: $pageScrollID,
                    selectionProgress: $selectionProgress,
                ) { page in
                    pageContent(for: page, model: model)
                }
            } else {
                ComicGridSkeletonView()
            }
        }
        .inlineLargeNavigationTitle("排行榜")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                SlidingTabSwitcher(
                    tabs: BikaRankingPage.all,
                    title: { $0.title },
                    selection: selectedPage,
                    selectionProgress: selectionProgress,
                    onSelect: select,
                )
            }
            // 切换组件自带玻璃背景，隐藏工具栏该位置自带的背景，避免叠成两层。
            .sharedBackgroundVisibility(.hidden)
        }
        .onAppear { prepareModelAndLoadIfNeeded() }
        .onChange(of: selectedPage) { _, page in
            model?.loadIfNeeded(for: page)
        }
    }

    /// 每个分页的内容：前三个周期同构，骑士榜是列表行。
    @ContentBuilder
    private func pageContent(for page: BikaRankingPage, model: BikaRankingModel) -> some View {
        switch page {
        case let .comic(period):
            BikaComicRankingPageContent(
                model: model.comicRankingModel(for: period),
                onSelectComic: { item in
                    open(item)
                },
            )

        case .knights:
            BikaKnightRankingPageContent(
                model: model.knights,
                onSelectKnight: { item in
                    openUploader(item)
                },
            )
        }
    }

    /// 首次展示时创建状态 owner 并加载当前分页；切 Tab 回来不重复请求。
    private func prepareModelAndLoadIfNeeded() {
        if model == nil {
            model = BikaRankingModel(services: services)
        }

        model?.loadIfNeeded(for: selectedPage)
    }

    /// 点标签：切页并让指示块跟着滑（与旧项目一致）。
    private func select(_ page: BikaRankingPage) {
        withAnimation(.snappy(duration: 0.24)) {
            selectedPage = page
            pageScrollID = page
        }
    }

    /// 点榜单卡片：push 本源漫画详情，跨来源转换由导航入口统一处理。
    private func open(_ item: ComicListItem) {
        shell.navigator.push(BikaRoute.detail(item.identity))
    }

    /// 点骑士榜条目：push 该上传者的作品列表。
    private func openUploader(_ item: BikaKnightRankingItem) {
        shell.navigator.push(
            BikaRoute.uploaderComics(id: item.accountID, name: item.displayName),
        )
    }
}

/// 一个周期的漫画榜内容：整份榜单一次性展示，没有分页。
private struct BikaComicRankingPageContent: View {
    let model: ComicPagingModel<BikaComicRankingPeriod, Int>
    let onSelectComic: (ComicListItem) -> Void

    var body: some View {
        InitialLoadView(
            model: model,
            initialState: { $0.loadState },
            isEmpty: { $0.items.isEmpty },
        ) {
            ComicGridSkeletonView()
        } empty: {
            EmptyStateView(title: "暂无排行内容", message: "稍后再来看看")
        } failure: { model, error in
            LoadErrorView(title: "排行榜加载失败", message: error.message) {
                model.retryInitialLoading()
            }
        } content: { model in
            ComicGridContent(
                items: model.items,
                onSelect: onSelectComic,
                isLoadingMore: false,
                canLoadMore: false,
                loadMoreErrorMessage: nil,
            )
        }
    }
}

/// 骑士榜内容：整份榜单一次性展示为列表行。
private struct BikaKnightRankingPageContent: View {
    let model: SourceValueLoadModel<[BikaKnightRankingItem]>
    let onSelectKnight: (BikaKnightRankingItem) -> Void

    var body: some View {
        InitialLoadView(
            model: model,
            initialState: { $0.phase },
            isEmpty: { $0.items.isEmpty },
        ) {
            BikaKnightRankingSkeletonView()
        } empty: {
            EmptyStateView(title: "暂无骑士排行", message: "稍后再来看看")
        } failure: { model, error in
            LoadErrorView(title: "骑士榜加载失败", message: error.message) {
                model.retry()
            }
        } content: { model in
            ScrollView(.vertical) {
                LazyVStack(spacing: 0) {
                    ForEach(model.items) { item in
                        Button {
                            onSelectKnight(item)
                        } label: {
                            BikaKnightRankingRow(item: item)
                                .contentShape(.rect)
                        }
                        .buttonStyle(.plain)

                        Divider()
                            .padding(.leading, 68)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .scrollIndicators(.hidden)
            .scrollToTopButton()
        }
    }
}

/// 展示一名骑士的头像、身份信息和上传数量。
private struct BikaKnightRankingRow: View {
    let item: BikaKnightRankingItem

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            avatar

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(item.displayName)
                        .font(.headline)
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)

                    Spacer(minLength: 0)

                    Text(verbatim: "\(item.uploadedComicCount)本")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.brandPrimary)
                        .fixedSize(horizontal: true, vertical: false)
                }

                Text(levelDescription)
                    .font(.caption)
                    .foregroundStyle(Color.textTertiary)
                    .lineLimit(1)

                if !item.slogan.isEmpty {
                    Text(item.slogan)
                        .font(.subheadline)
                        .foregroundStyle(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.vertical, 12)
    }

    /// 使用来源图片服务加载头像，缺失时显示本地系统占位。
    @ContentBuilder
    private var avatar: some View {
        if let avatar = item.avatar {
            ComicImageView(reference: avatar, targetSize: CGSize(width: 54, height: 54))
                .frame(width: 54, height: 54)
                .clipShape(.circle)
        } else {
            Circle()
                .fill(Color.surfaceElevated)
                .frame(width: 54, height: 54)
                .overlay {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 46))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(Color.iconSecondary)
                }
        }
    }

    /// 组合服务端称号和等级，不生成缺失字段的占位称号。
    private var levelDescription: String {
        guard !item.title.isEmpty else {
            return "Lv.\(item.level)"
        }

        return "\(item.title) · Lv.\(item.level)"
    }
}

/// 骑士榜骨架：头像圆 + 名称/数量/等级/简介占位，行高与真实条目交错一致。
private struct BikaKnightRankingSkeletonView: View {
    private let placeholderCount = 8

    var body: some View {
        ScrollView(.vertical) {
            LazyVStack(spacing: 0) {
                ForEach(0 ..< placeholderCount, id: \.self) { index in
                    BikaKnightRankingSkeletonRow(introductionLineCount: introductionLineCount(for: index))

                    Divider()
                        .padding(.leading, 68)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .skeletonLoadingEffect()
        }
        .scrollDisabled(true)
        .scrollIndicators(.hidden)
    }

    /// 交错模拟空简介、一行简介和多行简介对应的真实行高。
    private func introductionLineCount(for index: Int) -> Int {
        switch index % 3 {
        case 0:
            2
        case 1:
            1
        default:
            0
        }
    }
}

/// 骑士榜单行骨架。
private struct BikaKnightRankingSkeletonRow: View {
    let introductionLineCount: Int

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Circle()
                .fill(Color.textTertiary.opacity(0.18))
                .frame(width: 54, height: 54)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 12) {
                    SkeletonBlock(width: 112, height: 17)

                    Spacer(minLength: 0)

                    SkeletonBlock(width: 46, height: 15)
                }

                SkeletonBlock(width: 96, height: 12)

                if introductionLineCount > 0 {
                    VStack(alignment: .leading, spacing: 5) {
                        SkeletonBlock(height: 15)

                        if introductionLineCount > 1 {
                            SkeletonBlock(width: 156, height: 15)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

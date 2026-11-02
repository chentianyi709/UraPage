import SwiftUI

/// 禁漫首页分区内容：最上方是「随机推荐」，其后是服务端推广分区。
///
/// 随机推荐与推广分区来自两个接口，**各自加载、互不等待**：谁先完成谁先显示，
/// 另一个还在加载时保留自己的骨架（整页骨架与分区骨架同形，切换不跳变）。
/// 单个分区失败时在该分区位置就地提示并重试；两个分区都失败才由外层显示整页失败态。
/// 分区标题按 `JMComicHomeSectionNavigation` 决定是否可点：分类跳分类页，周刊与推广跳二级页面，
/// 静态分区只显示文案。
struct JMComicHomeSectionsView: View {
    /// 顶部随机推荐的数据阶段。
    let randomState: InitialValueLoadState<[ComicListItem]>

    /// 服务端推广分区的数据阶段。
    let sectionsState: InitialValueLoadState<[JMComicHomeSection]>

    let onSelectComic: (ComicListItem) -> Void

    /// 随机推荐加载失败后的就地重试。
    let onRetryRandom: () -> Void

    /// 推广分区加载失败后的就地重试。
    let onRetrySections: () -> Void

    /// 点击分类分区标题；`slug` 为服务端给出的分类值。
    let onSelectCategory: (String) -> Void

    /// 点击周刊分区标题；回传该分区的展示标题，页面据此设置周刊页标题。
    let onSelectWeekly: (String) -> Void

    /// 点击推广分区标题；回传该分区的服务端标识与展示标题（页面标题沿用分区名）。
    let onSelectPromotion: (_ sectionID: String, _ sectionTitle: String) -> Void

    /// 推广分区还在加载时显示的骨架段数（与常见分区数量一致）。
    private let loadingSectionCount = 3

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 24) {
                randomSection
                promotionSections
            }
            .padding(.vertical, ComicGridMetrics.verticalPadding)
        }
        .scrollToTopButton()
    }

    // MARK: - 随机推荐

    @ContentBuilder
    private var randomSection: some View {
        switch randomState {
        case .idle, .loading:
            ComicShelfSkeletonSection(showsDisclosureIndicator: false)

        case let .loaded(comics):
            ComicShelfSection(
                title: "随机推荐",
                items: comics,
                emptyText: "暂无随机推荐",
                onSelectComic: onSelectComic,
                coverOverlay: { JMComicUpdateOverlay(item: $0) },
            )

        case let .failed(error):
            SectionLoadFailureView(title: "随机推荐", message: error.message, onRetry: onRetryRandom)
        }
    }

    // MARK: - 推广分区

    @ContentBuilder
    private var promotionSections: some View {
        switch sectionsState {
        case .idle, .loading:
            ForEach(0 ..< loadingSectionCount, id: \.self) { _ in
                ComicShelfSkeletonSection(showsDisclosureIndicator: true)
            }

        case let .loaded(sections):
            ForEach(sections) { section in
                sectionContent(section)
            }

        case let .failed(error):
            SectionLoadFailureView(title: "推广", message: error.message, onRetry: onRetrySections)
        }
    }

    /// 单个分区：标题（按跳转语义可点）+ 两行横向卡片。
    ///
    /// 卡片与随机推荐共用公共分区组件；空分区不显示空态，保持服务端给的顺序即可。
    private func sectionContent(_ section: JMComicHomeSection) -> some View {
        ComicShelfSection(
            items: section.comics,
            emptyText: nil,
            onSelectComic: onSelectComic,
            coverOverlay: { JMComicUpdateOverlay(item: $0) },
        ) {
            sectionHeader(section)
        }
    }

    /// 分区标题：有跳转语义时是整行按钮（显示箭头提示），静态分区只显示文案。
    @ContentBuilder
    private func sectionHeader(_ section: JMComicHomeSection) -> some View {
        switch section.navigation {
        case let .category(slug):
            ComicSectionHeaderButton(title: section.title, accessibilityHint: "切换到分类页面") {
                onSelectCategory(slug)
            }

        case .weekly:
            ComicSectionHeaderButton(title: section.title, accessibilityHint: "打开周刊页面") {
                onSelectWeekly(section.title)
            }

        case .promotion:
            ComicSectionHeaderButton(title: section.title, accessibilityHint: "打开推广列表") {
                onSelectPromotion(section.id, section.title)
            }

        case .none:
            ComicSectionHeader(title: section.title, showsDisclosureIndicator: false)
        }
    }
}

import SwiftUI

/// 搜索页热门词区：服务端热门词胶囊、加载骨架、空态与分区级失败重试（与首页分区一致）。
///
/// 哔咔与禁漫共用：两者仅标题文案与数据来源不同，版式与三态一致；
/// 标题 + 胶囊走公共 `CapsuleSection`，骨架走公共 `CapsuleSectionSkeleton`，与书签页共用同一套版式；
/// 引导区通常与「最近搜索」共用同一滚动流：空态给固定最小高度保持居中，失败态保留标题并紧凑显示重试。
struct SourceHotSearchTermsView: View {
    /// 分区标题文案（由来源给出，如哔咔「热门搜索」、禁漫「热门成人主题」）。
    let title: String

    let model: SourceValueLoadModel<[String]>
    let onSelect: (String) -> Void

    /// 空态的最小高度（保持居中，不被上下内容挤压）。
    private static let stateMinHeight: CGFloat = 240

    var body: some View {
        InitialLoadView(
            model: model,
            initialState: { $0.phase },
            isEmpty: { $0.items.isEmpty },
        ) {
            skeleton
        } empty: {
            EmptyStateView(
                title: "暂无搜索推荐",
                message: "输入关键词后开始搜索",
                illustration: .search,
            )
            .frame(minHeight: Self.stateMinHeight)
        } failure: { model, error in
            // 与首页分区一致：保留分区标题，标题下方就地提示失败并重试，不用整页插图占位。
            CapsuleSection(title: title) {
                SectionLoadFailureContent(message: error.message, onRetry: model.retry)
            }
        } content: { model in
            content(model.items)
        }
    }

    /// 热门搜索标题与可点击的推荐词胶囊（外层统一滚动与内边距）。
    private func content(_ recommendations: [String]) -> some View {
        CapsuleSection(title: title) {
            ComicCapsuleList(
                values: recommendations,
                onSelect: onSelect,
            )
        }
    }

    /// 骨架屏：标题占位＋公共胶囊流骨架（与真实胶囊同排布），避免首屏形态跳变。
    private var skeleton: some View {
        CapsuleSectionSkeleton()
    }
}

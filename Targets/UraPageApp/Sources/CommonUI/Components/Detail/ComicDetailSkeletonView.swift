import SwiftUI

/// 详情页骨架：与真实内容同排布（顶部通栏封面块＋渐变、标题与字段行、阅读按钮、简介／标签分区）。
///
/// 在线详情的相关推荐使用三列卡片骨架，高度由内容撑开。
struct ComicDetailSkeletonView: View {
    /// 在线详情会展示相关推荐；离线详情没有相关推荐数据。
    let showsRelated: Bool

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 0) {
                heroSkeleton

                VStack(alignment: .leading, spacing: 0) {
                    metaSkeleton

                    SkeletonBlock(height: 48, cornerRadius: 18)
                        .padding(.vertical, 20)

                    VStack(alignment: .leading, spacing: 18) {
                        textSectionSkeleton(lineCount: 4)
                        tagSectionSkeleton
                        if showsRelated {
                            relatedSectionSkeleton
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
        }
        .scrollDisabled(true)
        .ignoresSafeArea(edges: .top)
        .skeletonLoadingEffect()
    }

    /// 顶部通栏封面块与底部渐变。
    private var heroSkeleton: some View {
        ZStack(alignment: .bottom) {
            Rectangle()
                .fill(Color.textTertiary.opacity(0.24))

            LinearGradient(
                colors: [
                    Color.pageBackground.opacity(0),
                    Color.pageBackground.opacity(0.72),
                    Color.pageBackground,
                ],
                startPoint: .top,
                endPoint: .bottom,
            )
            .frame(height: 120)
        }
        .frame(
            maxWidth: .infinity,
            minHeight: ComicDetailLayoutMetrics.heroHeight,
            maxHeight: ComicDetailLayoutMetrics.heroHeight,
        )
        .clipped()
    }

    /// 标题与统一字段行占位。
    private var metaSkeleton: some View {
        VStack(alignment: .leading, spacing: 10) {
            SkeletonBlock(width: 280, height: 28)

            HStack(spacing: 6) {
                Circle()
                    .fill(Color.textTertiary.opacity(0.18))
                    .frame(width: 12, height: 12)

                SkeletonBlock(width: 90, height: 12)
            }

            HStack(spacing: 12) {
                SkeletonBlock(width: 52, height: 12)
                SkeletonBlock(width: 52, height: 12)
                SkeletonBlock(width: 76, height: 12)
                SkeletonBlock(width: 54, height: 12)
            }
        }
    }

    /// 多行正文分区占位。
    private func textSectionSkeleton(lineCount: Int) -> some View {
        sectionSkeleton {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(0 ..< lineCount, id: \.self) { index in
                    SkeletonBlock(width: index == lineCount - 1 ? 200 : nil, height: 14)
                }
            }
        }
    }

    /// 标签分区胶囊占位。
    private var tagSectionSkeleton: some View {
        sectionSkeleton {
            HStack(spacing: 8) {
                ForEach(0 ..< 4, id: \.self) { _ in
                    Capsule()
                        .fill(Color.textTertiary.opacity(0.18))
                        .frame(width: 58, height: 28)
                }
            }
        }
    }

    /// 相关推荐三列卡片占位。
    private var relatedSectionSkeleton: some View {
        sectionSkeleton {
            ComicDetailRelatedSkeletonGrid()
        }
    }

    /// 带标题占位的详情分区。
    private func sectionSkeleton(@ContentBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                SkeletonBlock(width: 16, height: 16)
                SkeletonBlock(width: 84, height: 18)
            }

            content()
        }
    }
}

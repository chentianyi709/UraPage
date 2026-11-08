import Foundation
import SwiftUI

/// 详情页公共内容：顶部通栏封面（含下拉放大与底部渐变）＋标题＋作者与字段行＋阅读入口＋分区内容。
///
/// 版式与旧项目 `ComicDetailContentView` 一致：封面是固定高度的顶部 hero，标题与元信息在下方 12pt 边距内，
/// 分区间距 18。只负责“拿数据来画”：不取数、不决定路由；作者／标签组与阅读入口只保留回调。
/// 阅读进度由页面 owner 提供真实快照与动作；未提供时展示普通「开始阅读」。
struct ComicDetailContentView<Related: View>: View {
    /// 详情展示快照；在线与离线共用同一份具体值。
    let detail: DownloadedComicDetailSnapshot

    /// 阅读入口点击。
    let onStartReading: (() -> Void)?

    /// 已保存的阅读位置，由来源页面从公共记录 owner 读取。
    let readingProgress: ComicDetailReadingProgress?

    /// 是否有多个章节，决定继续阅读卡片的位置文案。
    let hasMultipleChapters: Bool

    /// 继续阅读入口点击。
    let onContinueReading: (() -> Void)?

    /// 作者名点击（下标＋名称）。
    let onSelectAuthorName: (Int, String) -> Void

    /// 标签组点击：参数是来源给的维度与清理过空白的展示名。
    let onSelectTag: (ComicTagKind, String) -> Void

    /// 点击作品 ID 时生成复制内容；`nil` 表示不显示复制入口。
    let copyContentProvider: ComicDetailCopyProvider?

    /// 相关推荐区；来源不需要时用空视图。
    @ContentBuilder let related: () -> Related

    /// 创建包含相关推荐槽的详情内容。
    init(
        detail: DownloadedComicDetailSnapshot,
        onStartReading: (() -> Void)?,
        readingProgress: ComicDetailReadingProgress? = nil,
        hasMultipleChapters: Bool = false,
        onContinueReading: (() -> Void)? = nil,
        onSelectAuthorName: @escaping (Int, String) -> Void,
        onSelectTag: @escaping (ComicTagKind, String) -> Void,
        copyContentProvider: ComicDetailCopyProvider? = nil,
        @ContentBuilder related: @escaping () -> Related,
    ) {
        self.detail = detail
        self.onStartReading = onStartReading
        self.readingProgress = readingProgress
        self.hasMultipleChapters = hasMultipleChapters
        self.onContinueReading = onContinueReading
        self.onSelectAuthorName = onSelectAuthorName
        self.onSelectTag = onSelectTag
        self.copyContentProvider = copyContentProvider
        self.related = related
    }

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 0) {
                hero

                VStack(alignment: .leading, spacing: 0) {
                    Text(detail.title.allowingLineBreakBetweenCharacters)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(Color.textPrimary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    ComicDetailMetadataSection(
                        authorNames: detail.authorNames,
                        metadata: detail.metadata,
                        comicID: detail.identity.comicID,
                        copyContentProvider: copyContentProvider,
                        onSelectAuthorName: onSelectAuthorName,
                    )

                    if onStartReading != nil || (readingProgress != nil && onContinueReading != nil) {
                        VStack(spacing: 8) {
                            if let onStartReading {
                                ComicDetailReadingButton(
                                    title: readingProgress == nil ? "开始阅读" : "重新开始阅读",
                                    action: onStartReading,
                                )
                            }

                            if let readingProgress, let onContinueReading {
                                ComicDetailContinueReadingCard(
                                    progress: readingProgress,
                                    hasMultipleChapters: hasMultipleChapters,
                                    action: onContinueReading,
                                )
                            }
                        }
                        .padding(.vertical, 20)
                    }

                    VStack(alignment: .leading, spacing: 18) {
                        if !detail.summary.isEmpty {
                            ComicDetailSection(title: "简介", systemImage: "text.alignleft") {
                                TruncatableText(detail.summary)
                                    .font(.body)
                                    .foregroundStyle(Color.textPrimary)
                                    .lineSpacing(4)
                            }
                        }

                        ForEach(visibleTagGroups) { group in
                            ComicDetailSection(title: group.kind.title, systemImage: group.kind.systemImage) {
                                ComicCapsuleList(values: group.values) { value in
                                    onSelectTag(group.kind, value)
                                }
                            }
                        }

                        related()
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 24)
                .visualEffect { content, geometry in
                    // 封面只增加一半下拉距离，正文同步下移相同距离，始终贴在封面下沿（与旧项目一致）。
                    let pullDownDistance = max(
                        geometry.frame(in: .scrollView(axis: .vertical)).minY
                            - ComicDetailLayoutMetrics.heroHeight,
                        0,
                    )

                    return content.offset(y: -pullDownDistance / 2)
                }
            }
        }
        .scrollIndicators(.hidden)
        .scrollToTopButton()
    }

    // MARK: - 顶部封面

    /// 顶部通栏封面：固定高度、底部渐隐到背景，下拉时整体拉伸放大（只做视觉变换，不改变图片尺寸）。
    ///
    /// 详情页作品大图直接用原图显示、不降采样，避免竖版封面被长边截断后放大发虚。
    private var hero: some View {
        GeometryReader { proxy in
            ComicCoverView(source: detail.cover, targetSize: proxy.size, downsamples: false)
                .visualEffect { content, geometry in
                    let pullDownDistance = max(
                        geometry.frame(in: .scrollView(axis: .vertical)).minY,
                        0,
                    )

                    return content.scaleEffect(1 + pullDownDistance / 1000)
                }
        }
        .frame(height: ComicDetailLayoutMetrics.heroHeight)
        .frame(maxWidth: .infinity)
        .clipped()
        .visualEffect { content, geometry in
            let pullDownDistance = max(
                geometry.frame(in: .scrollView(axis: .vertical)).minY,
                0,
            )
            let heightScale = (ComicDetailLayoutMetrics.heroHeight + pullDownDistance / 2) /
                ComicDetailLayoutMetrics.heroHeight

            return content
                .scaleEffect(heightScale, anchor: .top)
                .offset(y: -pullDownDistance)
        }
    }

    // MARK: - 过滤

    /// 去除来源值两端空白，并跳过没有可见内容的值。
    private func visibleValues(_ values: [String]) -> [String] {
        values.compactMap { value in
            let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmedValue.isEmpty ? nil : trimmedValue
        }
    }

    /// 过滤空值并丢掉整组为空的分组；组序与来源给的一致。
    private var visibleTagGroups: [ComicTagGroup] {
        assert(
            Set(detail.tagGroups.map(\.kind.id)).count == detail.tagGroups.count,
            "详情标签组出现重复维度：同一来源同一维度只能有一组，否则会撞 ForEach 身份",
        )
        return detail.tagGroups.compactMap { group in
            let values = visibleValues(group.values)
            return values.isEmpty ? nil : ComicTagGroup(kind: group.kind, values: values)
        }
    }
}

extension ComicDetailContentView where Related == EmptyView {
    /// 没有相关推荐区的详情内容。
    init(
        detail: DownloadedComicDetailSnapshot,
        onStartReading: (() -> Void)?,
        readingProgress: ComicDetailReadingProgress? = nil,
        hasMultipleChapters: Bool = false,
        onContinueReading: (() -> Void)? = nil,
        onSelectAuthorName: @escaping (Int, String) -> Void,
        onSelectTag: @escaping (ComicTagKind, String) -> Void,
        copyContentProvider: ComicDetailCopyProvider? = nil,
    ) {
        self.init(
            detail: detail,
            onStartReading: onStartReading,
            readingProgress: readingProgress,
            hasMultipleChapters: hasMultipleChapters,
            onContinueReading: onContinueReading,
            onSelectAuthorName: onSelectAuthorName,
            onSelectTag: onSelectTag,
            copyContentProvider: copyContentProvider,
            related: { EmptyView() },
        )
    }
}

/// 详情页展示阅读位置所需的最小快照；持久化与恢复由公共阅读记录负责。
struct ComicDetailReadingProgress: Sendable {
    let chapterTitle: String
    let pageIndex: Int
    let updatedAt: Date

    /// 位置与时间使用记录值，展示标题由详情中匹配的当前章节提供。
    init(_ progress: ReadingProgress, chapterTitle: String) {
        self.chapterTitle = chapterTitle
        pageIndex = progress.pageIndex
        updatedAt = progress.updatedAt
    }
}

/// 与旧版相同的继续阅读卡片；只有来源提供真实进度和动作时才显示。
private struct ComicDetailContinueReadingCard: View {
    let progress: ComicDetailReadingProgress
    let hasMultipleChapters: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(positionText)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)

                    Text("上次阅读：\(progress.updatedAt.formatted(date: .numeric, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                HStack(spacing: 4) {
                    Text("继续阅读")
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.brandPrimary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .background {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.surfaceElevated)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            "\(positionText)，上次阅读：\(progress.updatedAt.formatted(date: .numeric, time: .shortened))，继续阅读",
        )
    }

    private var positionText: String {
        if hasMultipleChapters {
            "\(progress.chapterTitle) · 第 \(progress.pageIndex + 1) 页"
        } else {
            "阅读到第 \(progress.pageIndex + 1) 页"
        }
    }
}

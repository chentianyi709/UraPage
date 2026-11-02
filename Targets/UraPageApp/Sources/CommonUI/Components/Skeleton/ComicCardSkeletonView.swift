import SwiftUI

/// 使用与漫画卡片一致的比例展示封面、标题和副标题占位内容。
struct ComicCardSkeletonView: View {
    @Environment(\.hidesComicCardSubtitles) private var hidesSubtitle

    let itemWidth: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SkeletonBlock(
                width: itemWidth,
                height: ComicGridMetrics.coverHeight(forItemWidth: itemWidth),
                cornerRadius: ComicGridMetrics.coverCornerRadius,
            )

            Text("漫画标题占位-漫画标题占位-漫画标题占位")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.textTertiary)
                .lineLimit(hidesSubtitle ? 2 : 1, reservesSpace: true)
                .redacted(reason: .placeholder)
                .frame(width: itemWidth * 0.82, alignment: .leading)
                .padding(.top, 6)

            if !hidesSubtitle {
                Text("副标题占位-副标题占位-副标题占位")
                    .font(.caption)
                    .foregroundStyle(Color.textTertiary.opacity(0.7))
                    .lineLimit(1, reservesSpace: true)
                    .redacted(reason: .placeholder)
                    .frame(width: itemWidth * 0.56, alignment: .leading)
                    .padding(.top, 4)
            }
        }
        .frame(width: itemWidth, alignment: .leading)
    }
}

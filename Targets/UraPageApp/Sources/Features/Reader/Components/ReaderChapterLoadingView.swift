import SwiftUI

/// 使用非交互的连续页面占位显示 Reader 章节首屏加载。
///
/// 继续阅读时从记录的目标页开始编号，避免加载期间先显示第 1 页再跳转。
struct ReaderChapterLoadingView: View {
    /// 首屏骨架的第一页页码（1-based）；首次阅读与切章从 1 开始。
    var startPageNumber: Int = 1

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                pagePlaceholder(number: startPageNumber, width: proxy.size.width)
                pagePlaceholder(number: startPageNumber + 1, width: proxy.size.width)
            }
        }
        .skeletonLoadingEffect()
    }

    /// 使用与 Canvas 图片占位一致的背景和页码样式绘制一张骨架页面。
    private func pagePlaceholder(
        number: Int,
        width: CGFloat,
    ) -> some View {
        Text(String(number))
            .font(.system(
                size: ReaderPagePlaceholderStyle.fontSize,
                weight: .black,
                design: .rounded,
            ))
            .foregroundStyle(
                Color.readerText.opacity(ReaderPagePlaceholderStyle.textOpacity),
            )
            .frame(width: width, height: width * 4 / 3)
            .background(Color.readerBackground)
    }
}

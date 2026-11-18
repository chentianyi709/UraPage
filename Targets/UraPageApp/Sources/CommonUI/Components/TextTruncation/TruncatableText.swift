import Foundation
import SwiftUI

/// 可展开的正文：默认折叠到 `lineLimit` 行、末行内嵌「展开」，展开后显示全文并追加「收起」。
///
/// 折叠与展开始终渲染**同一份文本**，只靠 `lineLimit` 截断。曾经给折叠态换了一份「压平换行」的
/// 文本，行数被算少：原文其实还有三段，折叠后只剩两行，明明放不下却判定成「无需展开」，
/// 展开入口随之消失。
///
/// 空行在入口处清掉——简介里常见连续空行，留着会把折叠区撑出一片空白；
/// 有内容的两行之间保留换行，行数才和真实内容一致。
struct TruncatableText: View {
    let text: String

    let lineLimit: Int

    let animation: Animation

    /// 折叠上限的高度（`lineLimit` 行）。
    @State private var collapsedHeight: CGFloat = 0

    /// 正文全文高度，只用于判断要不要展开——不含「收起」两个字，
    /// 否则末行刚好写满时会被那两个字多顶出一行，误判成可展开。
    @State private var textHeight: CGFloat = 0

    /// 正文加「收起」的高度，展开动画的目标值。
    @State private var expandedHeight: CGFloat = 0

    /// 0 收起、1 展开；由 `TextRenderer` 插值出中间态，容器高度同步插值。
    @State private var progress: CGFloat = 0

    init(
        _ text: String,
        lineLimit: Int = 2,
        animation: Animation = .smooth(duration: 0.22, extraBounce: 0),
    ) {
        self.text = Self.cleaned(text)
        self.lineLimit = max(lineLimit, 1)
        self.animation = animation
    }

    var body: some View {
        if text.isEmpty {
            EmptyView()
        } else {
            Button(action: toggle) {
                Text(text)
                    .lineLimit(lineLimit)
                    .opacity(0)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .readingHeight(into: $collapsedHeight)
                    .frame(height: visibleHeight, alignment: .top)
                    .overlay(alignment: .topLeading) {
                        GeometryReader { proxy in
                            ZStack(alignment: .topLeading) {
                                Text(text)
                                    .textRenderer(renderer(.collapsed, width: proxy.size.width))
                                    .fixedSize(horizontal: false, vertical: true)
                                    .readingHeight(into: $textHeight)

                                Text(expandedText)
                                    .textRenderer(renderer(.expanded, width: proxy.size.width))
                                    .fixedSize(horizontal: false, vertical: true)
                                    .readingHeight(into: $expandedHeight)
                            }
                            .frame(width: proxy.size.width, alignment: .topLeading)
                        }
                        .allowsHitTesting(false)
                    }
                    .clipped()
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            // 不可展开时只拦点击，不用 `.disabled`：它会把整段文字变灰，
            // 同一页里长短不一的简介就会一个深一个浅。
            .allowsHitTesting(isTruncatable)
            .accessibilityLabel(text)
            // 动画中途 `progress` 是小数，按一半判断比 `== 1` 稳。
            .accessibilityValue(progress > 0.5 ? "已展开" : "已收起")
            // 不可展开时点不动，别让读屏把它当按钮报出来。
            .accessibilityRemoveTraits(isTruncatable ? [] : .isButton)
            // 同一页面换了正文时整个回到初始态：收起、清掉上一条的测量值。
            // 高度清零后先按 `lineLimit` 行排版，等新测量到达再决定要不要展开，
            // 不会用旧高度或旧文案的判定画出中间态。
            .onChange(of: text) {
                progress = 0
                collapsedHeight = 0
                textHeight = 0
                expandedHeight = 0
            }
        }
    }

    /// 正文放不进折叠区才给展开入口。
    private var isTruncatable: Bool {
        collapsedHeight > 0 && textHeight > collapsedHeight + 0.5
    }

    /// 收起态与展开态之间的高度；高度还没测出来时不限制，避免首帧被压成 0。
    private var visibleHeight: CGFloat? {
        guard isTruncatable, collapsedHeight > 0 else {
            return nil
        }

        let target = expandedHeight > 0 ? expandedHeight : textHeight
        return collapsedHeight + (target - collapsedHeight) * progress
    }

    /// 展开态要在末尾追加「收起」，用带颜色的富文本，避免和正文同色。
    private var expandedText: AttributedString {
        var result = AttributedString(text)
        guard isTruncatable else {
            return result
        }

        var indicator = AttributedString(" 收起")
        indicator.foregroundColor = Color.brandPrimary
        result += indicator
        return result
    }

    private func renderer(
        _ presentation: TextTruncationTextRenderer.Presentation,
        width: CGFloat,
    ) -> TextTruncationTextRenderer {
        TextTruncationTextRenderer(
            presentation: presentation,
            showsIndicator: isTruncatable,
            length: lineLimit,
            containerWidth: width,
            progress: progress,
        )
    }

    private func toggle() {
        guard isTruncatable else {
            return
        }

        withAnimation(animation) {
            progress = progress == 0 ? 1 : 0
        }
    }

    /// 去掉空行与每行首尾空白，保留有内容行之间的换行。
    ///
    /// 简介里的连续空行只是排版噪音，留着会把折叠区撑出一片空白；
    /// 但也不能压成一行——那会把行数算少，折叠态明明还有内容却判定为放得下。
    ///
    /// 调用方需要判断「这段文本清理后还有没有内容」时可以直接用它，
    /// 只由空行组成的简介不会留下一块空白的简介区。
    static func cleaned(_ text: String) -> String {
        guard text.rangeOfCharacter(from: .newlines) != nil else {
            return text
        }

        return text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }
}

private extension View {
    /// 把视图高度写回状态，只在实际变化超过半像素时提交——文字测量的亚像素抖动不该反复触发布局。
    func readingHeight(into height: Binding<CGFloat>) -> some View {
        onGeometryChange(for: CGSize.self) {
            $0.size
        } action: { size in
            guard abs(height.wrappedValue - size.height) > 0.5 else {
                return
            }

            height.wrappedValue = size.height
        }
    }
}

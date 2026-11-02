import Foundation
import SwiftUI

/// 收起时使用连续文字填满指定行数，展开后恢复原文的换行。
struct TruncatableText: View {
    let text: String
    let collapsedText: String
    let lineLimit: Int
    let animation: Animation

    @State private var limitedSize: CGSize = .zero
    @State private var fullSize: CGSize = .zero
    @State private var animationProgress: CGFloat = 0

    init(
        _ text: String,
        lineLimit: Int = 2,
        animation: Animation = .smooth(duration: 0.22, extraBounce: 0),
    ) {
        self.text = text
        collapsedText = Self.makeCollapsedText(from: text)
        self.lineLimit = max(lineLimit, 1)
        self.animation = animation
    }

    private var isTruncatable: Bool {
        text != collapsedText ||
            (limitedSize.height > 0 && fullSize.height > limitedSize.height + 0.5)
    }

    private var visibleHeight: CGFloat? {
        guard isTruncatable, limitedSize.height > 0 else {
            return nil
        }

        return limitedSize.height +
            (fullSize.height - limitedSize.height) * animationProgress
    }

    var body: some View {
        Button {
            withAnimation(animation) {
                animationProgress = animationProgress == 0 ? 1 : 0
            }
        } label: {
            Text(collapsedText)
                .lineLimit(lineLimit)
                .opacity(0)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .onGeometryChange(for: CGSize.self) {
                    $0.size
                } action: { newValue in
                    guard sizeHasMeaningfullyChanged(from: limitedSize, to: newValue) else {
                        return
                    }

                    limitedSize = newValue
                }
                .frame(height: visibleHeight, alignment: .top)
                .overlay(alignment: .topLeading) {
                    GeometryReader { proxy in
                        ZStack(alignment: .topLeading) {
                            Text(collapsedText)
                                .textRenderer(
                                    TextTruncationTextRenderer(
                                        presentation: .collapsed,
                                        showsIndicator: isTruncatable,
                                        length: lineLimit,
                                        containerWidth: proxy.size.width,
                                        progress: animationProgress,
                                    ),
                                )
                                .fixedSize(horizontal: false, vertical: true)

                            Text(expandedText)
                                .textRenderer(
                                    TextTruncationTextRenderer(
                                        presentation: .expanded,
                                        showsIndicator: isTruncatable,
                                        length: lineLimit,
                                        containerWidth: proxy.size.width,
                                        progress: animationProgress,
                                    ),
                                )
                                .fixedSize(horizontal: false, vertical: true)
                                .onGeometryChange(for: CGSize.self) {
                                    $0.size
                                } action: { newValue in
                                    guard sizeHasMeaningfullyChanged(from: fullSize, to: newValue) else {
                                        return
                                    }

                                    fullSize = newValue
                                }
                        }
                        .frame(width: proxy.size.width, alignment: .topLeading)
                    }
                    .allowsHitTesting(false)
                }
                .clipped()
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isTruncatable)
        .accessibilityLabel(text)
        .accessibilityValue(animationProgress == 1 ? "已展开" : "已收起")
    }

    /// 只整理换行：空行被移除，有文字的相邻行用一个空格连接。
    private static func makeCollapsedText(from text: String) -> String {
        guard text.rangeOfCharacter(from: .newlines) != nil else {
            return text
        }

        return text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// 让「收起」参与正常排版：末行放不下时自动换行，不牺牲原文末尾字符。
    private var expandedText: AttributedString {
        var result = AttributedString(text)
        guard isTruncatable else { return result }

        var indicator = AttributedString(" 收起")
        indicator.foregroundColor = Color.brandPrimary
        result += indicator
        return result
    }

    /// 忽略文字测量中的亚像素抖动，只提交会影响布局的变化。
    private func sizeHasMeaningfullyChanged(from oldSize: CGSize, to newSize: CGSize) -> Bool {
        abs(oldSize.width - newSize.width) > 0.5 ||
            abs(oldSize.height - newSize.height) > 0.5
    }
}

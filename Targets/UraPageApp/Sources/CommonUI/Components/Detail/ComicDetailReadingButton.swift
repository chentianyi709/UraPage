import SwiftUI

/// 详情页「开始阅读」按钮：品牌色圆角块＋白色文字，阴影挂背景形状。
struct ComicDetailReadingButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: "book.pages.fill")
                .font(.headline.weight(.semibold))
                .foregroundStyle(Color.textOnPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background {
                    RoundedRectangle(cornerRadius: 18)
                        .fill(Color.brandPrimary)
                        .shadow(color: Color.shadow.opacity(0.12), radius: 8, x: 0, y: 3)
                }
        }
        .buttonStyle(.plain)
    }
}

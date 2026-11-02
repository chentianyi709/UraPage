import SwiftUI

/// 绘制登录与账号资料的背景与柔和色彩光晕（公共）。
///
/// 登录表单与已登录资料页共用同一张背景；颜色全部取自主题色板，
/// 深浅色都成立。
struct SourceLoginBackground: View {
    var body: some View {
        ZStack {
            Color.pageBackground
                .ignoresSafeArea()

            GeometryReader { proxy in
                Circle()
                    .fill(Color.brandPrimary.opacity(0.22))
                    .frame(width: proxy.size.width * 0.9, height: proxy.size.width * 0.9)
                    .blur(radius: 70)
                    .offset(x: -proxy.size.width * 0.25, y: -proxy.size.height * 0.15)

                Circle()
                    .fill(Color.brandPrimary.opacity(0.14))
                    .frame(width: proxy.size.width * 0.7, height: proxy.size.width * 0.7)
                    .blur(radius: 60)
                    .offset(x: proxy.size.width * 0.35, y: proxy.size.height * 0.45)

                RoundedRectangle(cornerRadius: 100)
                    .fill(Color.brandPrimary.opacity(0.10))
                    .frame(width: proxy.size.width * 0.6, height: proxy.size.width * 0.6)
                    .blur(radius: 80)
                    .rotationEffect(.degrees(45))
                    .offset(x: proxy.size.width * 0.2, y: proxy.size.height * 0.05)
            }
            .ignoresSafeArea()
        }
    }
}

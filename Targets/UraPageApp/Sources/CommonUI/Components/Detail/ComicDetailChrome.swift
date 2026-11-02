import SwiftUI

/// 详情页统一外壳：底色铺满、保留控件安全区、导航栏透明且不显示标题。
///
/// 顶部工具栏右侧固定展示当前作品来源的圆形 Logo（在线／离线详情共用）；
/// 来源信息读 `\.sourceDescriptor`，由来源 Module 的 destination 边界安装。
struct ComicDetailChrome<Content: View>: View {
    @Environment(\.sourceDescriptor) private var descriptor

    let title: String?
    @ContentBuilder let content: () -> Content

    var body: some View {
        ZStack {
            Color.pageBackground.ignoresSafeArea()

            content()
        }
        .ignoresSafeArea(edges: .top)
        .navigationTitle(title ?? "漫画详情")
        .toolbar(removing: .title)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                // 36 是「贴着导航栏玻璃底高度上限」的最大值（上限约 40，44 起会被压成横向椭圆），
                // 想再放大就得同时接受椭圆底。
                SourceLogoView(descriptor.logo, size: 36, outline: .circle)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .scrollEdgeEffectHidden(true, for: .top)
    }
}

extension View {
    /// 套上详情页统一外壳。
    func comicDetailChrome(title: String?) -> some View {
        ComicDetailChrome(title: title) { self }
    }
}

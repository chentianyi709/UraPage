import SwiftUI

/// 来源 Tab 根页面（首页等）的公共外壳：来源展示名大标题 + 右上角来源切换与账号入口。
///
/// 右上角依次是「切换漫画源」（当前来源的圆形 Logo）与「账号与设置」（头像图标），
/// 两者各占一个工具栏项、中间留固定间距，是两个独立的圆按钮而不是一颗胶囊。
/// 头像在对应来源已登录时使用主体色，其余状态（检查中／未登录／失败）用常规文字色：
/// 登录事实由来源体验根安装的 `\.sourceAccountAccess` 提供（恢复也由体验根触发），这里只读取。
/// 设置弹窗走 **App 级 sheet 路由**（在最外层呈现，内容由本源 Module 提供），这里只调用 App Shell 能力。
private struct SourceRootChromeModifier: ViewModifier {
    @Environment(\.sourcePresentation) private var presentation
    @Environment(\.sourceDescriptor) private var descriptor
    @Environment(\.sourceAccountAccess) private var accountAccess

    func body(content: Content) -> some View {
        // 已登录（含恢复完成后）用主体色；检查中、未登录与失败都用常规色。
        let accountColor = accountAccess?.current == .authenticated ? Color.brandPrimary : Color.textPrimary

        return content
            .inlineLargeNavigationTitle(descriptor.displayName)
            .toolbar {
                // 两个入口各占一个工具栏项，中间用 `ToolbarSpacer` 隔开：
                // 同组（或只是简单相邻）的工具栏项会被 iOS 26 并成同一颗玻璃胶囊，看起来像一个控件。
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        presentation.presentSourceSelection()
                    } label: {
                        // 和详情页工具栏同一做法：36pt 圆形 Logo。玻璃底必须用 `.plain` 才会是正圆——
                        // 默认按钮样式会给内容加左右内边距，玻璃底按「内容＋内边距」绘制，
                        // 宽度超过高度就成了横椭圆（30pt 时实测 50×44）。
                        SourceLogoView(descriptor.logo, size: 36, outline: .circle)
                    }
                    .buttonStyle(.plain)
                    .tint(Color.textPrimary)
                    .accessibilityLabel("切换漫画源")
                }

                ToolbarSpacer(.fixed, placement: .topBarTrailing)

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        presentation.presentSourceSettings(for: descriptor.sourceID)
                    } label: {
                        Image(systemName: "person.crop.circle")
                            .foregroundStyle(accountColor)
                    }
                    .tint(accountColor)
                    .accessibilityLabel("打开账号与设置")
                }
            }
    }
}

extension View {
    /// 挂上来源根页面的公共外壳（标题、来源切换入口与账号入口）。
    func sourceRootChrome() -> some View {
        modifier(SourceRootChromeModifier())
    }
}

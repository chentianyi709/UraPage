import SwiftUI

extension View {
    /// 使用 iOS 26 的 inlineLarge 样式显示导航标题：大号标题内联在工具栏中，不随滚动折叠。
    ///
    /// 来源首页与各列表页统一使用它，保证标题位置与旧版一致；
    /// 需要传统大标题（滚动折叠）时直接用 `navigationTitle` 即可。
    func inlineLargeNavigationTitle(_ title: String) -> some View {
        navigationTitle(title)
            .toolbarTitleDisplayMode(.inlineLarge)
    }
}

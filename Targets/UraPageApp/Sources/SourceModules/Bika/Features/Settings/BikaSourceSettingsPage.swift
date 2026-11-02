import SwiftUI

/// 哔咔「漫画源设置」分页：非阅读图片清晰度、图片 CDN 加速与服务器线路切换。
///
/// 哔咔只有固定候选地址，不做远程发现；线路在每次启动时自动获取，页面只提供切换。
struct BikaSourceSettingsPage: View {
    @Environment(\.bikaServices) private var services

    var body: some View {
        SourceHostSettingsPage(services: services) { services in
            BikaImageSettingsContent(services: services)
        }
    }
}

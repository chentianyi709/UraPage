import SwiftUI

/// 绅士「漫画源设置」分页：服务器线路切换。
///
/// 其它来源设置随各自能力接入后加入本页。
struct ShenshiSourceSettingsPage: View {
    @Environment(\.shenshiServices) private var services

    var body: some View {
        SourceHostSettingsPage(services: services)
    }
}

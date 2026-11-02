import SwiftUI

/// 通用设置（App 级、所有来源一致）：外观、缓存、阅读历史、下载与清理。
///
/// 每个分区各自持有页面状态与二次确认，根视图只负责组合；
/// 「清理」分区的动作与文案由 `GeneralCleanupModel` 承担。
struct GeneralSettingsView: View {
    var body: some View {
        Form {
            GeneralAppearanceSection()
            GeneralCacheLimitSection()
            GeneralReadingHistorySection()
            GeneralDownloadSection()
            GeneralCleanupSection()
        }
    }
}

import SwiftUI

/// 承载可以即时生效并持久化的 Reader 设置。
struct ReaderSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.readerSettings) private var settings

    var body: some View {
        @Bindable var settings = settings

        NavigationStack {
            Form {
                Section {
                    Picker("主题模式", selection: $settings.themeMode) {
                        ForEach(ThemeMode.allCases) { mode in
                            Text(themeTitle(for: mode))
                                .tag(mode)
                        }
                    }

                    Picker("阅读控件显示方式", selection: $settings.chromeToggleMode) {
                        ForEach(ReaderChromeToggleMode.allCases) { mode in
                            Text(mode.title)
                                .tag(mode)
                        }
                    }
                } footer: {
                    Text("跟随 App 时使用全局主题；其他模式只影响阅读页面。滚动时，阅读控件仍会自动隐藏。")
                }

                Section {
                    Toggle(
                        "隐藏控制栏时禁用滑动返回",
                        isOn: $settings.disablesSwipeBackWhenChromeHidden,
                    )
                } footer: {
                    Text("开启后，阅读控制栏隐藏时无法滑动返回；显示控制栏后可从任意位置右滑返回。")
                }
            }
            .navigationTitle("阅读设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: dismiss.callAsFunction) {
                        Image(systemName: "xmark")
                            .foregroundStyle(.primary)
                    }
                    .tint(.primary)
                    .accessibilityLabel("关闭")
                }
            }
        }
        .appNavigationBarScrollEdgeEffect()
        .tint(.accent)
    }

    /// 返回 Reader 主题选择面向用户的文案。
    private func themeTitle(for mode: ThemeMode) -> String {
        mode == .system ? "跟随 App" : mode.title
    }
}

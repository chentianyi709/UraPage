import SwiftUI

/// 通用设置「外观」分区：主题模式与卡片副标题。
struct GeneralAppearanceSection: View {
    @Environment(\.appearanceSettings) private var appearanceSettings

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 12) {
                    Text("主题模式")

                    Spacer(minLength: 16)

                    Picker("主题模式", selection: themeModeBinding) {
                        ForEach(ThemeMode.allCases) { mode in
                            Text(mode.title)
                                .tag(mode)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                }

                Text("「黑暗模式」让整个 App 使用深色外观；「跟随系统」随系统设置切换。")
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Toggle("隐藏卡片副标题", isOn: hidesComicCardSubtitlesBinding)

                Text("开启后，所有漫画卡片只显示标题，标题固定占用两行。")
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
            }
        } header: {
            Text("外观")
        }
    }

    /// 读 owner 当前值、切换写回 owner（页面不直接读写持久化）。
    private var hidesComicCardSubtitlesBinding: Binding<Bool> {
        Binding(
            get: { appearanceSettings.hidesComicCardSubtitles },
            set: { appearanceSettings.setHidesComicCardSubtitles($0) },
        )
    }

    /// 读 owner 当前值、选择写回 owner（页面不直接读写持久化）。
    private var themeModeBinding: Binding<ThemeMode> {
        Binding(
            get: { appearanceSettings.themeMode },
            set: { appearanceSettings.select($0) },
        )
    }
}

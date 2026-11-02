import SwiftUI

/// 来源设置页里的服务器线路设置项：显示线路名与当前地址，并提供候选切换。
///
/// 由各来源设置页放进同一个「漫画源设置」列表分区（不再自带分组）；请求与错误边界由传入的
/// `SourceHostSettingsModel` 承担。线路在每次启动时自动获取，因此没有手动刷新入口；
/// 当前地址放在本行下方，失败时同一位置显示错误（避免与重试按钮重复成两行）。
///
/// 选择控件用公共 `MenuPicker`：菜单每项显示「线路名 + 域名」两行并带勾选，
/// SwiftUI 的 `Picker(.menu)` 做不到副标题（详见 `MenuPicker` 的说明）。
struct SourceHostSettingsContent: View {
    let model: SourceHostSettingsModel

    /// 其它设置正在改动 Client 状态时禁用本项（两边都写同一个 Client）。
    var isExternallyDisabled = false

    /// 当前线路：标题行（右侧线路选择）＋下方当前地址。
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 12) {
                Text("当前线路")

                Spacer(minLength: 8)

                hostControl
            }

            if let errorMessage = model.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(Color.error)
            } else if let snapshot = model.snapshot {
                Text(hostText(of: snapshot.activeBaseURL))
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }

    /// 选择控件：已加载为菜单，加载中显示进度，失败给出重试入口。
    @ContentBuilder
    private var hostControl: some View {
        if let snapshot = model.snapshot {
            MenuPicker(
                elements: pickerElements(snapshot),
                selection: snapshot.activeBaseURL,
                isEnabled: !model.isBusy && !isExternallyDisabled,
                onSelect: selectCandidate,
            )
        } else if model.isLoading {
            ProgressView()
                .controlSize(.small)
        } else if model.errorMessage != nil {
            // 只有加载失败（而非首次加载前）才给出重试入口，避免刚出现时闪一下按钮。
            Button("重新加载", action: model.retry)
        }
    }

    /// 菜单项：主标题是线路名，副标题是域名。
    ///
    /// 身份用地址：快照构建时已按地址去重，同一个地址只会有一项被选中；
    /// 菜单展开期间快照被替换时提交的仍是用户看到的那条线路。
    private func pickerElements(
        _ snapshot: SourceHostSelectionSnapshot,
    ) -> [MenuPickerElement<URL>] {
        snapshot.candidates.map { candidate in
            .item(
                id: candidate.baseURL,
                title: candidate.title,
                subtitle: hostText(of: candidate.baseURL),
            )
        }
    }

    /// 提交选择：地址就是候选身份，快照在菜单展开期间被替换也只提交用户点到的地址。
    private func selectCandidate(_ baseURL: URL) {
        model.select(baseURL)
    }

    /// 只显示域名；解析失败时退回完整地址。
    private func hostText(of baseURL: URL) -> String {
        baseURL.host ?? baseURL.absoluteString
    }
}

import SwiftUI

/// 禁漫「漫画源设置」里的图源设置项：显示当前图源与实际图片 Host，并支持切换。
///
/// 由页面放进同一个「漫画源设置」列表分区（不再自带分组）。数据与提交由
/// `JMComicImageSourceSettingsModel` 承担（读取、切换、失败回滚）；
/// 本视图只负责三种状态（加载中／失败重试／可选）与选择控件。
/// 失败反馈走公共 `ToastCenter`（与来源设置的其它操作一致），行内保留重试入口。
struct JMComicImageSourceSettingsContent: View {
    let model: JMComicImageSourceSettingsModel

    /// 其它设置正在改动 Client 状态时禁用选择（两边都写同一个 Client）。
    var isExternallyDisabled = false

    var body: some View {
        imageSourceRow
            .onChange(of: model.errorMessage) { _, errorMessage in
                guard let errorMessage else {
                    return
                }

                ToastCenter.shared.show(errorMessage, type: .error)
            }
    }

    /// 图片图源：标题行（右侧选择控件）＋下方说明。
    private var imageSourceRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 12) {
                Text("图片图源")

                Spacer(minLength: 16)

                // Host 操作与 Setting 重载连续显示进度，整行保持同一结构。
                if model.isBusy || isExternallyDisabled {
                    ProgressView()
                        .controlSize(.small)
                        .tint(Color.brandPrimary)
                        .accessibilityLabel("正在加载图源")
                }

                if !model.isLoading, !isExternallyDisabled {
                    imageSourceControl
                }
            }

            imageSourceSubtitle
        }
    }

    /// 选择／空态／重试入口；进度独立放在固定行内，避免与菜单一起被替换。
    @ContentBuilder
    private var imageSourceControl: some View {
        if let snapshot = model.snapshot, !snapshot.imageSources.isEmpty {
            Picker("图片图源", selection: imageSourceSelection(fallback: snapshot.selectedKey)) {
                ForEach(snapshot.imageSources) { imageSource in
                    Text(imageSource.title)
                        .tag(imageSource.key)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .tint(Color.brandPrimary)
            .disabled(model.isUpdating)
        } else if model.snapshot != nil {
            Text("暂无可选")
                .foregroundStyle(Color.textSecondary)
        } else if model.errorMessage != nil {
            Button("重新加载", action: model.reload)
        }
    }

    /// 行下方说明：当前实际图片域名；尚未就绪时显示加载提示。
    @ContentBuilder
    private var imageSourceSubtitle: some View {
        if let activeImageHost = model.snapshot?.activeImageHost {
            Text(activeImageHost.host ?? activeImageHost.absoluteString)
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
        } else if model.isLoading {
            Text("正在加载中")
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
        }
    }

    /// 把菜单选择交给模型提交；失败由模型回滚到已确认值。
    private func imageSourceSelection(fallback: Int) -> Binding<Int> {
        Binding(
            get: { model.displayedKey ?? fallback },
            set: { model.select($0) },
        )
    }
}
